import { z } from 'zod';

export const peerIDSchema = z.string().regex(/^[a-f0-9]{64}$/u);
export const packetIDSchema = z.string().uuid();
export const isoDateSchema = z.string().datetime({ offset: true });
export const sealedPayloadSchema = z.string().min(16).regex(/^[A-Za-z0-9+/]+={0,2}$/u);
export const signatureSchema = z.string().min(64).regex(/^[A-Za-z0-9+/]+={0,2}$/u);

export const outboundTransportPacketSchema = z.object({
  protocolVersion: z.literal(2),
  id: packetIDSchema,
  senderID: peerIDSchema,
  recipientID: peerIDSchema,
  sealedPayloadBase64: sealedPayloadSchema,
  signatureBase64: signatureSchema,
  createdAt: isoDateSchema,
  expiresAt: isoDateSchema
});

export const fetchQuerySchema = z.object({
  recipientID: peerIDSchema,
  limit: z.coerce.number().int().min(1).max(100).default(50)
});

export const deleteParamsSchema = z.object({
  packetID: packetIDSchema
});

export const purgeRecipientBodySchema = z.object({
  recipientID: peerIDSchema
});

export type OutboundTransportPacket = z.infer<typeof outboundTransportPacketSchema>;
export type FetchQuery = z.infer<typeof fetchQuerySchema>;
export type DeleteParams = z.infer<typeof deleteParamsSchema>;
export type PurgeRecipientBody = z.infer<typeof purgeRecipientBodySchema>;

export interface RelaySendResponse {
  readonly accepted: boolean;
  readonly packetID: string;
}

export interface RelayFetchResponse {
  readonly packets: readonly OutboundTransportPacket[];
}

export interface RelayDeleteResponse {
  readonly deleted: boolean;
  readonly packetID: string;
}

export interface RelayPurgeResponse {
  readonly deletedCount: number;
  readonly recipientID: string;
}

export interface RelayStatsResponse {
  readonly storedPackets: number;
  readonly activeRecipients: number;
  readonly acknowledgedPacketTombstones: number;
}
