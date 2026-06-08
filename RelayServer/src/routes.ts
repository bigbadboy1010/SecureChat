import { timingSafeEqual } from 'node:crypto';
import { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import { z } from 'zod';
import { type RelayConfig } from './config.js';
import { RelayHttpError } from './errors.js';
import {
  deleteParamsSchema,
  fetchQuerySchema,
  outboundTransportPacketSchema,
  purgeRecipientBodySchema,
  type DeleteParams,
  type FetchQuery,
  type PurgeRecipientBody,
  type RelayDeleteResponse,
  type RelayFetchResponse,
  type RelayPurgeResponse,
  type RelaySendResponse,
  type RelayStatsResponse
} from './schemas.js';
import { type RelayStore } from './store.js';

interface RegisterRelayRoutesOptions {
  readonly app: FastifyInstance;
  readonly config: RelayConfig;
  readonly store: RelayStore;
}

interface RelayHealthResponse {
  readonly status: 'ok';
  readonly store: 'memory' | 'file';
  readonly authRequired: boolean;
  readonly adminAuthRequired: boolean;
  readonly productionMode: boolean;
  readonly httpsRequired: boolean;
  readonly clientPurgeEnabled: boolean;
  readonly maxPacketBytes: number;
  readonly maxTTLSeconds: number;
  readonly maxClockSkewSeconds: number;
  readonly maxTotalPackets: number;
  readonly maxPacketsPerRecipient: number;
}

interface RelaySecurityPolicyResponse {
  readonly productionMode: boolean;
  readonly store: 'memory' | 'file';
  readonly authRequired: boolean;
  readonly adminAuthRequired: boolean;
  readonly httpsRequired: boolean;
  readonly clientPurgeEnabled: boolean;
  readonly rateLimitMax: number;
  readonly rateLimitWindow: string;
  readonly maxPacketBytes: number;
  readonly maxTTLSeconds: number;
  readonly maxClockSkewSeconds: number;
  readonly maxTotalPackets: number;
  readonly maxPacketsPerRecipient: number;
  readonly encryptedPayloadOnly: true;
}

export async function registerRelayRoutes(options: RegisterRelayRoutesOptions): Promise<void> {
  const { app, config, store } = options;

  app.addHook('preHandler', async (request: FastifyRequest): Promise<void> => {
    if (request.url.startsWith('/v1/relay') || request.url.startsWith('/v1/admin')) {
      enforceHTTPSPolicy(request, config);
    }

    if (request.url.startsWith('/v1/admin')) {
      requireBearerToken(request, config.adminToken, 'Admin authorization required');
      return;
    }

    if (request.url.startsWith('/v1/relay')) {
      if (config.authToken !== null) {
        requireBearerToken(request, config.authToken, 'Unauthorized');
      }
    }
  });

  app.addHook('onResponse', async (request, reply) => {
    if (config.securityAuditLog === false) {
      return;
    }
    if (request.url.startsWith('/v1/relay') || request.url.startsWith('/v1/admin')) {
      request.log.info(
        {
          method: request.method,
          path: sanitizePath(request.url),
          statusCode: reply.statusCode,
          requestID: request.id
        },
        'Relay security audit'
      );
    }
  });

  app.get('/health', async (): Promise<RelayHealthResponse> => ({
    status: 'ok',
    store: config.storeType,
    authRequired: config.authToken !== null,
    adminAuthRequired: config.adminToken !== null,
    productionMode: config.nodeEnv === 'production',
    httpsRequired: config.nodeEnv === 'production' && config.requireHTTPSInProduction,
    clientPurgeEnabled: config.allowClientPurge,
    maxPacketBytes: config.maxPacketBytes,
    maxTTLSeconds: config.maxTTLSeconds,
    maxClockSkewSeconds: config.maxClockSkewSeconds,
    maxTotalPackets: config.maxTotalPackets,
    maxPacketsPerRecipient: config.maxPacketsPerRecipient
  }));

  app.get('/v1/relay/security/policy', async (): Promise<RelaySecurityPolicyResponse> => securityPolicy(config));

  app.get('/v1/relay/stats', async (): Promise<RelayStatsResponse> => {
    await store.cleanupExpired(new Date());
    return store.stats();
  });

  app.post('/v1/relay/messages', async (request: FastifyRequest, reply: FastifyReply): Promise<RelaySendResponse> => {
    const packet = outboundTransportPacketSchema.parse(request.body);
    validatePacket(packet, config);
    await store.cleanupExpired(new Date());
    await enforceStoreCapacity(packet.recipientID, store, config);
    await store.put(packet);
    reply.code(202);
    return { accepted: true, packetID: packet.id };
  });

  app.get('/v1/relay/messages', async (request: FastifyRequest): Promise<RelayFetchResponse> => {
    const query = fetchQuerySchema.parse(request.query) satisfies FetchQuery;
    await store.cleanupExpired(new Date());
    const packets = await store.list(query.recipientID, query.limit);
    return { packets };
  });

  app.post('/v1/relay/messages/purge', async (request: FastifyRequest): Promise<RelayPurgeResponse> => {
    if (config.allowClientPurge === false) {
      throw new RelayHttpError(403, 'Client purge is disabled by relay policy');
    }
    const body = purgeRecipientBodySchema.parse(request.body) satisfies PurgeRecipientBody;
    const deletedCount = await store.purgeRecipient(body.recipientID);
    return { deletedCount, recipientID: body.recipientID };
  });

  app.delete('/v1/relay/messages/:packetID', async (request: FastifyRequest): Promise<RelayDeleteResponse> => acknowledgePacket(request, store));

  app.post('/v1/relay/messages/:packetID/ack', async (request: FastifyRequest): Promise<RelayDeleteResponse> => acknowledgePacket(request, store));

  app.get('/v1/admin/relay/security/policy', async (): Promise<RelaySecurityPolicyResponse> => securityPolicy(config));

  app.get('/v1/admin/relay/stats', async (): Promise<RelayStatsResponse> => {
    await store.cleanupExpired(new Date());
    return store.stats();
  });

  app.post('/v1/admin/relay/messages/purge', async (request: FastifyRequest): Promise<RelayPurgeResponse> => {
    const body = purgeRecipientBodySchema.parse(request.body) satisfies PurgeRecipientBody;
    const deletedCount = await store.purgeRecipient(body.recipientID);
    return { deletedCount, recipientID: body.recipientID };
  });
}

async function acknowledgePacket(request: FastifyRequest, store: RelayStore): Promise<RelayDeleteResponse> {
  const params = deleteParamsSchema.parse(request.params) satisfies DeleteParams;

  try {
    const deleted = await store.delete(params.packetID);
    return { deleted, packetID: params.packetID };
  } catch {
    return { deleted: false, packetID: params.packetID };
  }
}

async function enforceStoreCapacity(recipientID: string, store: RelayStore, config: RelayConfig): Promise<void> {
  const stats = await store.stats();
  if (stats.storedPackets >= config.maxTotalPackets) {
    throw new RelayHttpError(507, 'Relay packet capacity exceeded');
  }

  const recipientCount = await store.recipientPacketCount(recipientID);
  if (recipientCount >= config.maxPacketsPerRecipient) {
    throw new RelayHttpError(429, 'Recipient relay queue limit exceeded');
  }
}

function validatePacket(packet: z.infer<typeof outboundTransportPacketSchema>, config: RelayConfig): void {
  if (packet.senderID === packet.recipientID) {
    throw new RelayHttpError(400, 'Sender and recipient must differ');
  }

  const payloadBytes = Buffer.byteLength(packet.sealedPayloadBase64, 'base64');
  if (payloadBytes > config.maxPacketBytes) {
    throw new RelayHttpError(413, 'Packet too large');
  }

  const createdAtTime = Date.parse(packet.createdAt);
  const expiresAtTime = Date.parse(packet.expiresAt);
  const nowTime = Date.now();

  if (Number.isNaN(createdAtTime) || Number.isNaN(expiresAtTime)) {
    throw new RelayHttpError(400, 'Invalid packet timestamp');
  }

  if (expiresAtTime <= createdAtTime) {
    throw new RelayHttpError(400, 'Packet expiry must be after creation time');
  }

  if (expiresAtTime <= nowTime) {
    throw new RelayHttpError(400, 'Packet already expired');
  }

  const clockSkewMilliseconds = config.maxClockSkewSeconds * 1000;
  if (createdAtTime > nowTime + clockSkewMilliseconds) {
    throw new RelayHttpError(400, 'Packet creation time is too far in the future');
  }

  if (createdAtTime < nowTime - (config.maxTTLSeconds * 1000) - clockSkewMilliseconds) {
    throw new RelayHttpError(400, 'Packet creation time is outside relay policy window');
  }

  const ttlSeconds = Math.ceil((expiresAtTime - createdAtTime) / 1000);
  if (ttlSeconds > config.maxTTLSeconds) {
    throw new RelayHttpError(400, 'Packet TTL exceeds policy');
  }
}

function securityPolicy(config: RelayConfig): RelaySecurityPolicyResponse {
  return {
    productionMode: config.nodeEnv === 'production',
    store: config.storeType,
    authRequired: config.authToken !== null,
    adminAuthRequired: config.adminToken !== null,
    httpsRequired: config.nodeEnv === 'production' && config.requireHTTPSInProduction,
    clientPurgeEnabled: config.allowClientPurge,
    rateLimitMax: config.rateLimitMax,
    rateLimitWindow: config.rateLimitWindow,
    maxPacketBytes: config.maxPacketBytes,
    maxTTLSeconds: config.maxTTLSeconds,
    maxClockSkewSeconds: config.maxClockSkewSeconds,
    maxTotalPackets: config.maxTotalPackets,
    maxPacketsPerRecipient: config.maxPacketsPerRecipient,
    encryptedPayloadOnly: true
  };
}

function enforceHTTPSPolicy(request: FastifyRequest, config: RelayConfig): void {
  if (config.nodeEnv !== 'production' || config.requireHTTPSInProduction === false) {
    return;
  }

  const forwardedProto = firstHeaderValue(request.headers['x-forwarded-proto'])?.toLowerCase();
  const forwardedSSL = firstHeaderValue(request.headers['x-forwarded-ssl'])?.toLowerCase();
  const isSecure = forwardedProto === 'https' || forwardedSSL === 'on' || request.protocol === 'https';
  if (isSecure === false) {
    throw new RelayHttpError(426, 'HTTPS is required by relay policy');
  }
}

function requireBearerToken(request: FastifyRequest, expectedToken: string | null, message: string): void {
  if (expectedToken === null) {
    throw new RelayHttpError(403, message);
  }

  const authorization = request.headers.authorization ?? '';
  const prefix = 'Bearer ';
  if (authorization.startsWith(prefix) === false) {
    throw new RelayHttpError(401, message);
  }

  const receivedToken = authorization.slice(prefix.length);
  if (constantTimeEquals(receivedToken, expectedToken) === false) {
    throw new RelayHttpError(401, message);
  }
}

function constantTimeEquals(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left, 'utf8');
  const rightBuffer = Buffer.from(right, 'utf8');
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return timingSafeEqual(leftBuffer, rightBuffer);
}

function firstHeaderValue(value: string | string[] | undefined): string | undefined {
  if (Array.isArray(value)) {
    return value[0];
  }
  return value;
}

function sanitizePath(url: string): string {
  return url.split('?')[0] ?? url;
}
