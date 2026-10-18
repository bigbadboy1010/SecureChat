//! Narrow, stateless C bridge around vodozemac's Olm implementation.
//! Every successful operation returns a *candidate* state. The caller must
//! durably commit it with the corresponding inbox/outbox record before use.
//! No fallback keys, initial roots, or private bootstrap-key copies are kept.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::BTreeMap, ffi::{c_char, CString}, panic::catch_unwind};
use vodozemac::{olm::{Account, AccountPickle, OlmMessage, Session, SessionConfig, SessionPickle}, Curve25519PublicKey};
use zeroize::Zeroize;

const MAX_INPUT: usize = 16 * 1024 * 1024;
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct State { version: u8, account: AccountPickle, peers: BTreeMap<String, Peer> }
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Peer { identity: String, sessions: BTreeMap<String, SessionPickle> }
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    action: String,
    state: Option<State>,
    peer: Option<String>,
    identity: Option<String>,
    one_time_key: Option<String>,
    session_id: Option<String>,
    plaintext: Option<String>,
    message: Option<OlmMessage>,
    count: Option<usize>,
    remove_keys: Option<Vec<String>>,
}
fn required(v: Option<String>) -> Result<String, &'static str> { v.ok_or("missing_parameter") }
fn key(s: &str) -> Result<Curve25519PublicKey, &'static str> {
    let k = Curve25519PublicKey::from_base64(s).map_err(|_| "invalid_key")?;
    if k.to_base64() != s { return Err("noncanonical_key"); }
    Ok(k)
}
fn run(input: &[u8]) -> Result<Value, &'static str> {
    let r: Request = serde_json::from_slice(input).map_err(|_| "invalid_request")?;
    if r.action == "new" {
        if r.state.is_some() { return Err("existing_state"); }
        let account = Account::new();
        return Ok(json!({"state": State { version: 1, account: account.pickle(), peers: BTreeMap::new() }, "identity": account.curve25519_key().to_base64()}));
    }
    let mut state = r.state.ok_or("missing_state")?;
    if state.version != 1 || state.peers.len() > 256 { return Err("invalid_state"); }
    let mut account = Account::from_pickle(state.account);
    let mut result = json!({});
    match r.action.as_str() {
        "keys" => {
            let count = r.count.unwrap_or(0);
            if count > 50 || account.stored_one_time_key_count() + count > 1000 { return Err("key_capacity"); }
            if !account.one_time_keys().is_empty() && count != 0 { return Err("unpublished_keys"); }
            account.generate_one_time_keys(count);
            let keys: BTreeMap<_, _> = account.one_time_keys().into_iter().map(|(id, k)| (id.to_base64(), k.to_base64())).collect();
            result = json!({"identity": account.curve25519_key().to_base64(), "keys": keys});
        }
        "published" => { account.mark_keys_as_published(); }
        "remove_keys" => {
            let keys = r.remove_keys.ok_or("missing_parameter")?;
            if keys.len() > 1000 { return Err("key_capacity"); }
            for k in keys { account.remove_one_time_key(key(&k)?); }
        }
        "outbound" | "encrypt" | "decrypt" => {
            let peer_id = required(r.peer)?;
            if peer_id.len() != 64 || !peer_id.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) { return Err("invalid_peer"); }
            let identity = required(r.identity)?;
            let identity_key = key(&identity)?;
            if identity_key == account.curve25519_key() { return Err("self_session"); }
            if let Some(peer) = state.peers.get(&peer_id) {
                if peer.identity != identity { return Err("identity_changed"); }
            } else if state.peers.len() >= 256 { return Err("peer_capacity"); }
            let peer = state.peers.entry(peer_id).or_insert_with(|| Peer { identity, sessions: BTreeMap::new() });
            if r.action == "outbound" {
                if peer.sessions.len() >= 8 { return Err("session_capacity"); }
                let session = account.create_outbound_session(SessionConfig::version_1(), identity_key, key(&required(r.one_time_key)?)?).map_err(|_| "bootstrap_failed")?;
                let id = session.session_id();
                peer.sessions.insert(id.clone(), session.pickle());
                result = json!({"session_id": id});
            } else if r.action == "encrypt" {
                let id = required(r.session_id)?;
                let pickle = peer.sessions.remove(&id).ok_or("missing_session")?;
                let mut session = Session::from_pickle(pickle);
                let plaintext = required(r.plaintext)?;
                if plaintext.len() > 120_000 { return Err("payload_capacity"); }
                let message = session.encrypt(plaintext).map_err(|_| "encryption_failed")?;
                peer.sessions.insert(id.clone(), session.pickle());
                result = json!({"session_id": id, "message": message});
            } else {
                let id = required(r.session_id)?;
                let message = r.message.ok_or("missing_parameter")?;
                let plaintext;
                if let Some(pickle) = peer.sessions.remove(&id) {
                    let mut session = Session::from_pickle(pickle);
                    plaintext = session.decrypt(&message).map_err(|_| "decryption_failed")?;
                    peer.sessions.insert(id, session.pickle());
                } else {
                    if peer.sessions.len() >= 8 { return Err("session_capacity"); }
                    let OlmMessage::PreKey(prekey) = message else { return Err("missing_session"); };
                    if prekey.session_id() != id { return Err("session_mismatch"); }
                    let inbound = account.create_inbound_session(SessionConfig::version_1(), identity_key, &prekey).map_err(|_| "bootstrap_failed")?;
                    plaintext = inbound.plaintext;
                    peer.sessions.insert(id, inbound.session.pickle());
                }
                result = json!({"plaintext": String::from_utf8(plaintext).map_err(|_| "invalid_plaintext")?});
            }
        }
        _ => return Err("unknown_action"),
    }
    state.account = account.pickle();
    result["state"] = serde_json::to_value(state).map_err(|_| "serialization_failed")?;
    Ok(result)
}

/// Input bytes must be valid for `len`; returned NUL-terminated JSON is owned
/// by this library and must be released exactly once using pr_olm_free.
#[no_mangle]
pub unsafe extern "C" fn pr_olm_execute(input: *const u8, len: usize) -> *mut c_char {
    let result = catch_unwind(|| {
        if input.is_null() || len == 0 || len > MAX_INPUT { return json!({"error":"invalid_input"}); }
        match run(std::slice::from_raw_parts(input, len)) {
            Ok(value) => value,
            Err(error) => json!({"error":error}),
        }
    }).unwrap_or_else(|_| json!({"error":"internal_failure"}));
    // JSON escaping guarantees that the result has no embedded NUL.
    CString::new(result.to_string()).expect("JSON contains no raw NUL").into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn pr_olm_free(buffer: *mut c_char) {
    if !buffer.is_null() {
        let string = CString::from_raw(buffer);
        let mut bytes = string.into_bytes_with_nul();
        bytes.zeroize();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn exec(r: Value) -> Value { run(r.to_string().as_bytes()).expect("operation") }
    fn fresh() -> Value { exec(json!({"action":"new"})) }
    fn peers() -> (Value, Value, String) {
        let mut a = fresh(); let mut b = fresh();
        let keys = exec(json!({"action":"keys","state":b["state"],"count":2}));
        let otk = keys["keys"].as_object().unwrap().values().next().unwrap().as_str().unwrap().to_owned();
        b["state"] = exec(json!({"action":"published","state":keys["state"]}))["state"].take();
        let s = exec(json!({"action":"outbound","state":a["state"],"peer":"b".repeat(64),"identity":b["identity"],"one_time_key":otk}));
        a["state"] = s["state"].clone(); (a,b,s["session_id"].as_str().unwrap().into())
    }
    fn encrypt(a: &mut Value, b: &Value, sid: &str, text: &str) -> Value {
        let r = exec(json!({"action":"encrypt","state":a["state"],"peer":"b".repeat(64),"identity":b["identity"],"session_id":sid,"plaintext":text}));
        a["state"] = r["state"].clone(); r["message"].clone()
    }
    fn receive(b: &mut Value, a: &Value, sid: &str, m: &Value) -> Result<Value, &'static str> {
        let r = run(json!({"action":"decrypt","state":b["state"],"peer":"a".repeat(64),"identity":a["identity"],"session_id":sid,"message":m}).to_string().as_bytes())?;
        b["state"] = r["state"].clone(); Ok(r)
    }
    #[test] fn delivered_past_ciphertext_unreadable_from_current_state() {
        let (mut a, mut b, sid) = peers();
        let m = encrypt(&mut a, &b, &sid, "past secret");
        assert_eq!(receive(&mut b,&a,&sid,&m).unwrap()["plaintext"],"past secret");
        assert!(receive(&mut b,&a,&sid,&m).is_err());
        // Removing the current sessions cannot reconstruct bootstrap: the
        // receiver's consumed one-time private key was durably removed too.
        b["state"]["peers"] = json!({});
        assert!(receive(&mut b,&a,&sid,&m).is_err());
    }
    #[test] fn offline_reordering_and_persistence() {
        let (mut a, mut b, sid) = peers();
        let first = encrypt(&mut a,&b,&sid,"first");
        let second = encrypt(&mut a,&b,&sid,"second");
        assert_eq!(receive(&mut b,&a,&sid,&second).unwrap()["plaintext"],"second");
        b = serde_json::from_str(&b.to_string()).unwrap();
        assert_eq!(receive(&mut b,&a,&sid,&first).unwrap()["plaintext"],"first");
        assert!(receive(&mut b,&a,&sid,&first).is_err());
    }
    #[test] fn fresh_dh_turns_heal_a_passively_compromised_session_snapshot() {
        let (mut a, mut b, sid) = peers();
        let initial = encrypt(&mut a,&b,&sid,"initial");
        receive(&mut b,&a,&sid,&initial).unwrap();
        let compromised_a = a["state"].clone();
        // Bob replies with fresh DH entropy. Alice then answers with fresh DH
        // entropy too. A passive attacker retaining Alice's previous state
        // cannot follow the next Bob sending chain after this complete turn.
        let reply = exec(json!({"action":"encrypt","state":b["state"],"peer":"a".repeat(64),"identity":a["identity"],"session_id":sid,"plaintext":"first reply"}));
        b["state"] = reply["state"].clone();
        let seen = exec(json!({"action":"decrypt","state":a["state"],"peer":"b".repeat(64),"identity":b["identity"],"session_id":sid,"message":reply["message"]}));
        a["state"] = seen["state"].clone();
        let answer = encrypt(&mut a,&b,&sid,"fresh Alice DH");
        receive(&mut b,&a,&sid,&answer).unwrap();
        let healed = exec(json!({"action":"encrypt","state":b["state"],"peer":"a".repeat(64),"identity":a["identity"],"session_id":sid,"plaintext":"after recovery turn"}));
        let attempt = json!({"action":"decrypt","state":compromised_a,"peer":"b".repeat(64),"identity":b["identity"],"session_id":sid,"message":healed["message"]});
        assert!(run(attempt.to_string().as_bytes()).is_err());
        let legitimate = exec(json!({"action":"decrypt","state":a["state"],"peer":"b".repeat(64),"identity":b["identity"],"session_id":sid,"message":healed["message"]}));
        assert_eq!(legitimate["plaintext"], "after recovery turn");
    }
    #[test] fn bad_message_does_not_consume_one_time_key_or_advance_state() {
        let (mut a, mut b, sid) = peers();
        let m = encrypt(&mut a,&b,&sid,"authentic"); let before = b.clone();
        let mut bad = m.clone(); let body = bad["body"].as_str().unwrap().to_owned();
        let mut bytes = vodozemac::base64_decode(&body).unwrap(); let last = bytes.len()-1; bytes[last] ^= 1;
        bad["body"] = json!(vodozemac::base64_encode(bytes));
        assert!(receive(&mut b,&a,&sid,&bad).is_err()); assert_eq!(b,before);
        assert!(receive(&mut b,&a,&sid,&m).is_ok());
    }
}
