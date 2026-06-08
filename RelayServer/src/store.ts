import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { RelayHttpError } from './errors.js';
import { type OutboundTransportPacket } from './schemas.js';

export interface RelayStoreStats {
  readonly storedPackets: number;
  readonly activeRecipients: number;
  readonly acknowledgedPacketTombstones: number;
}

export interface RelayStore {
  put(packet: OutboundTransportPacket): Promise<void>;
  list(recipientID: string, limit: number): Promise<readonly OutboundTransportPacket[]>;
  delete(packetID: string): Promise<boolean>;
  purgeRecipient(recipientID: string): Promise<number>;
  cleanupExpired(now: Date): Promise<number>;
  stats(): Promise<RelayStoreStats>;
  recipientPacketCount(recipientID: string): Promise<number>;
}


interface StoredTombstone {
  readonly packetID: string;
  readonly acknowledgedAt: string;
}

interface FileRelayStoreState {
  readonly packets: readonly OutboundTransportPacket[];
  readonly acknowledgedPacketIDs: readonly StoredTombstone[];
}

abstract class BaseRelayStore implements RelayStore {
  protected static readonly maxTombstones = 10_000;

  protected readonly packetsByID = new Map<string, OutboundTransportPacket>();
  protected readonly packetIDsByRecipient = new Map<string, Set<string>>();
  protected readonly acknowledgedPacketIDs = new Map<string, Date>();

  public async put(packet: OutboundTransportPacket): Promise<void> {
    await this.beforeMutationOrRead();
    this.compactTombstonesIfNeeded();

    if (this.packetsByID.has(packet.id) || this.acknowledgedPacketIDs.has(packet.id)) {
      throw new RelayHttpError(409, 'Packet already exists or was already acknowledged');
    }

    this.packetsByID.set(packet.id, packet);
    const recipientPackets = this.packetIDsByRecipient.get(packet.recipientID) ?? new Set<string>();
    recipientPackets.add(packet.id);
    this.packetIDsByRecipient.set(packet.recipientID, recipientPackets);
    await this.afterMutation();
  }

  public async list(recipientID: string, limit: number): Promise<readonly OutboundTransportPacket[]> {
    await this.beforeMutationOrRead();
    const packetIDs = this.packetIDsByRecipient.get(recipientID) ?? new Set<string>();
    const packets: OutboundTransportPacket[] = [];
    const stalePacketIDs: string[] = [];

    for (const packetID of packetIDs) {
      if (this.acknowledgedPacketIDs.has(packetID)) {
        stalePacketIDs.push(packetID);
        continue;
      }

      const packet = this.packetsByID.get(packetID);
      if (packet !== undefined) {
        packets.push(packet);
      } else {
        stalePacketIDs.push(packetID);
      }

      if (packets.length >= limit) {
        break;
      }
    }

    if (stalePacketIDs.length > 0) {
      for (const stalePacketID of stalePacketIDs) {
        packetIDs.delete(stalePacketID);
      }
      if (packetIDs.size === 0) {
        this.packetIDsByRecipient.delete(recipientID);
      }
      await this.afterMutation();
    }

    return packets.sort((left, right) => left.createdAt.localeCompare(right.createdAt));
  }

  public async delete(packetID: string): Promise<boolean> {
    await this.beforeMutationOrRead();
    this.acknowledgedPacketIDs.set(packetID, new Date());
    this.compactTombstonesIfNeeded();

    const packet = this.packetsByID.get(packetID);
    if (packet === undefined) {
      this.removePacketIDFromAllRecipients(packetID);
      await this.afterMutation();
      return false;
    }

    this.packetsByID.delete(packetID);
    const recipientPackets = this.packetIDsByRecipient.get(packet.recipientID);
    recipientPackets?.delete(packetID);
    if (recipientPackets !== undefined && recipientPackets.size === 0) {
      this.packetIDsByRecipient.delete(packet.recipientID);
    }
    await this.afterMutation();
    return true;
  }

  public async purgeRecipient(recipientID: string): Promise<number> {
    await this.beforeMutationOrRead();
    const packetIDs = this.packetIDsByRecipient.get(recipientID) ?? new Set<string>();
    let deleted = 0;

    for (const packetID of packetIDs) {
      this.acknowledgedPacketIDs.set(packetID, new Date());
      if (this.packetsByID.delete(packetID)) {
        deleted += 1;
      }
    }

    this.packetIDsByRecipient.delete(recipientID);
    this.compactTombstonesIfNeeded();
    await this.afterMutation();
    return deleted;
  }

  public async cleanupExpired(now: Date): Promise<number> {
    await this.beforeMutationOrRead();
    const nowTime = now.getTime();
    let deleted = 0;

    for (const packet of [...this.packetsByID.values()]) {
      if (Date.parse(packet.expiresAt) <= nowTime) {
        this.acknowledgedPacketIDs.set(packet.id, new Date());
        this.packetsByID.delete(packet.id);
        const recipientPackets = this.packetIDsByRecipient.get(packet.recipientID);
        recipientPackets?.delete(packet.id);
        if (recipientPackets !== undefined && recipientPackets.size === 0) {
          this.packetIDsByRecipient.delete(packet.recipientID);
        }
        deleted += 1;
      }
    }

    if (deleted > 0) {
      this.compactTombstonesIfNeeded();
      await this.afterMutation();
    }
    return deleted;
  }

  public async stats(): Promise<RelayStoreStats> {
    await this.beforeMutationOrRead();
    return {
      storedPackets: this.packetsByID.size,
      activeRecipients: this.packetIDsByRecipient.size,
      acknowledgedPacketTombstones: this.acknowledgedPacketIDs.size
    };
  }

  public async recipientPacketCount(recipientID: string): Promise<number> {
    await this.beforeMutationOrRead();
    return this.packetIDsByRecipient.get(recipientID)?.size ?? 0;
  }

  protected async beforeMutationOrRead(): Promise<void> {
    // Implemented by persistent stores when lazy loading is required.
  }

  protected async afterMutation(): Promise<void> {
    // Implemented by persistent stores when writes must be flushed.
  }

  protected rebuildRecipientIndex(): void {
    this.packetIDsByRecipient.clear();
    for (const packet of this.packetsByID.values()) {
      const recipientPackets = this.packetIDsByRecipient.get(packet.recipientID) ?? new Set<string>();
      recipientPackets.add(packet.id);
      this.packetIDsByRecipient.set(packet.recipientID, recipientPackets);
    }
  }

  private removePacketIDFromAllRecipients(packetID: string): void {
    for (const [recipientID, packetIDs] of this.packetIDsByRecipient.entries()) {
      packetIDs.delete(packetID);
      if (packetIDs.size === 0) {
        this.packetIDsByRecipient.delete(recipientID);
      }
    }
  }

  protected compactTombstonesIfNeeded(): void {
    if (this.acknowledgedPacketIDs.size <= BaseRelayStore.maxTombstones) {
      return;
    }

    const tombstones = [...this.acknowledgedPacketIDs.entries()].sort((left, right) => left[1].getTime() - right[1].getTime());
    const tombstonesToDelete = tombstones.slice(0, tombstones.length - BaseRelayStore.maxTombstones);
    for (const [packetID] of tombstonesToDelete) {
      this.acknowledgedPacketIDs.delete(packetID);
    }
  }
}

export class InMemoryRelayStore extends BaseRelayStore {}

export class FileRelayStore extends BaseRelayStore {
  private readonly statePath: string;
  private readonly tempStatePath: string;
  private isLoaded = false;
  private writeQueue: Promise<void> = Promise.resolve();

  public constructor(dataDir: string) {
    super();
    this.statePath = join(dataDir, 'relay-store.json');
    this.tempStatePath = join(dataDir, 'relay-store.json.tmp');
  }

  protected override async beforeMutationOrRead(): Promise<void> {
    if (this.isLoaded) {
      return;
    }

    try {
      const data = await readFile(this.statePath, 'utf8');
      const parsed = JSON.parse(data) as Partial<FileRelayStoreState>;
      this.packetsByID.clear();
      this.acknowledgedPacketIDs.clear();

      for (const packet of parsed.packets ?? []) {
        this.packetsByID.set(packet.id, packet);
      }

      for (const tombstone of parsed.acknowledgedPacketIDs ?? []) {
        const acknowledgedAt = new Date(tombstone.acknowledgedAt);
        if (Number.isNaN(acknowledgedAt.getTime()) === false) {
          this.acknowledgedPacketIDs.set(tombstone.packetID, acknowledgedAt);
        }
      }

      this.rebuildRecipientIndex();
      this.compactTombstonesIfNeeded();
      this.isLoaded = true;
    } catch (error: unknown) {
      if (isNodeFileNotFoundError(error)) {
        this.isLoaded = true;
        return;
      }
      throw error;
    }
  }

  protected override async afterMutation(): Promise<void> {
    const packets = [...this.packetsByID.values()];
    const acknowledgedPacketIDs: StoredTombstone[] = [...this.acknowledgedPacketIDs.entries()].map(([packetID, acknowledgedAt]) => ({
      packetID,
      acknowledgedAt: acknowledgedAt.toISOString()
    }));
    const state: FileRelayStoreState = { packets, acknowledgedPacketIDs };

    this.writeQueue = this.writeQueue.then(async () => {
      await mkdir(dirname(this.statePath), { recursive: true });
      await writeFile(this.tempStatePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
      await rename(this.tempStatePath, this.statePath);
    });

    await this.writeQueue;
  }
}

function isNodeFileNotFoundError(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 'ENOENT';
}
