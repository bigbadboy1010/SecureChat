import { z } from 'zod';

const booleanStringSchema = z.preprocess((value) => {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['1', 'true', 'yes', 'on'].includes(normalized)) {
      return true;
    }
    if (['0', 'false', 'no', 'off'].includes(normalized)) {
      return false;
    }
  }
  return value;
}, z.boolean());

const optionalBooleanStringSchema = booleanStringSchema.optional();

const environmentSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().min(1).default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65_535).default(8080),
  MAX_PACKET_BYTES: z.coerce.number().int().min(1024).max(1_048_576).default(131_072),
  MAX_TTL_SECONDS: z.coerce.number().int().min(60).max(604_800).default(86_400),
  MAX_CLOCK_SKEW_SECONDS: z.coerce.number().int().min(0).max(86_400).default(300),
  MAX_TOTAL_PACKETS: z.coerce.number().int().min(1).max(1_000_000).default(10_000),
  MAX_PACKETS_PER_RECIPIENT: z.coerce.number().int().min(1).max(100_000).default(500),
  RATE_LIMIT_MAX: z.coerce.number().int().min(1).max(10_000).default(120),
  RATE_LIMIT_WINDOW: z.string().min(1).default('1 minute'),
  STORE_TYPE: z.enum(['memory', 'file']).default('memory'),
  DATA_DIR: z.string().min(1).default('./data'),
  RELAY_AUTH_TOKEN: z.string().optional().default(''),
  RELAY_ADMIN_TOKEN: z.string().optional().default(''),
  REQUIRE_AUTH_IN_PRODUCTION: optionalBooleanStringSchema,
  REQUIRE_HTTPS_IN_PRODUCTION: optionalBooleanStringSchema,
  TRUST_PROXY_HEADERS: optionalBooleanStringSchema,
  ENABLE_CLIENT_PURGE: optionalBooleanStringSchema,
  SECURITY_AUDIT_LOG: optionalBooleanStringSchema,
  MIN_AUTH_TOKEN_LENGTH: z.coerce.number().int().min(16).max(256).default(32)
});

export interface RelayConfig {
  readonly nodeEnv: 'development' | 'test' | 'production';
  readonly host: string;
  readonly port: number;
  readonly maxPacketBytes: number;
  readonly maxTTLSeconds: number;
  readonly maxClockSkewSeconds: number;
  readonly maxTotalPackets: number;
  readonly maxPacketsPerRecipient: number;
  readonly rateLimitMax: number;
  readonly rateLimitWindow: string;
  readonly storeType: 'memory' | 'file';
  readonly dataDir: string;
  readonly authToken: string | null;
  readonly adminToken: string | null;
  readonly requireAuthInProduction: boolean;
  readonly requireHTTPSInProduction: boolean;
  readonly trustProxyHeaders: boolean;
  readonly allowClientPurge: boolean;
  readonly securityAuditLog: boolean;
  readonly minAuthTokenLength: number;
}

export function loadConfig(env: NodeJS.ProcessEnv): RelayConfig {
  const parsed = environmentSchema.parse(env);
  const trimmedToken = parsed.RELAY_AUTH_TOKEN.trim();
  const trimmedAdminToken = parsed.RELAY_ADMIN_TOKEN.trim();
  const isProduction = parsed.NODE_ENV === 'production';
  const requireAuthInProduction = parsed.REQUIRE_AUTH_IN_PRODUCTION ?? true;
  const requireHTTPSInProduction = parsed.REQUIRE_HTTPS_IN_PRODUCTION ?? true;
  const trustProxyHeaders = parsed.TRUST_PROXY_HEADERS ?? true;
  const allowClientPurge = parsed.ENABLE_CLIENT_PURGE ?? !isProduction;
  const securityAuditLog = parsed.SECURITY_AUDIT_LOG ?? true;

  if (isProduction && requireAuthInProduction) {
    if (trimmedToken.length < parsed.MIN_AUTH_TOKEN_LENGTH) {
      throw new Error(`RELAY_AUTH_TOKEN must be at least ${parsed.MIN_AUTH_TOKEN_LENGTH} characters in production`);
    }
    if (trimmedAdminToken.length > 0 && trimmedAdminToken.length < parsed.MIN_AUTH_TOKEN_LENGTH) {
      throw new Error(`RELAY_ADMIN_TOKEN must be at least ${parsed.MIN_AUTH_TOKEN_LENGTH} characters in production when configured`);
    }
  }

  if (isProduction && parsed.STORE_TYPE !== 'file') {
    throw new Error('STORE_TYPE=file is required in production so queued encrypted packets survive restarts');
  }

  return {
    nodeEnv: parsed.NODE_ENV,
    host: parsed.HOST,
    port: parsed.PORT,
    maxPacketBytes: parsed.MAX_PACKET_BYTES,
    maxTTLSeconds: parsed.MAX_TTL_SECONDS,
    maxClockSkewSeconds: parsed.MAX_CLOCK_SKEW_SECONDS,
    maxTotalPackets: parsed.MAX_TOTAL_PACKETS,
    maxPacketsPerRecipient: parsed.MAX_PACKETS_PER_RECIPIENT,
    rateLimitMax: parsed.RATE_LIMIT_MAX,
    rateLimitWindow: parsed.RATE_LIMIT_WINDOW,
    storeType: parsed.STORE_TYPE,
    dataDir: parsed.DATA_DIR,
    authToken: trimmedToken.length > 0 ? trimmedToken : null,
    adminToken: trimmedAdminToken.length > 0 ? trimmedAdminToken : null,
    requireAuthInProduction,
    requireHTTPSInProduction,
    trustProxyHeaders,
    allowClientPurge,
    securityAuditLog,
    minAuthTokenLength: parsed.MIN_AUTH_TOKEN_LENGTH
  };
}
