import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyError } from 'fastify';
import { ZodError } from 'zod';
import { loadConfig } from './config.js';
import { errorMessage, RelayHttpError } from './errors.js';
import { registerRelayRoutes } from './routes.js';
import { FileRelayStore, InMemoryRelayStore } from './store.js';

const config = loadConfig(process.env);
const app = Fastify({
  logger: config.nodeEnv !== 'test',
  bodyLimit: config.maxPacketBytes * 2,
  trustProxy: config.trustProxyHeaders
});

app.addHook('onSend', async (_request, reply, payload) => {
  reply.header('Cache-Control', 'no-store');
  reply.header('Pragma', 'no-cache');
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('Referrer-Policy', 'no-referrer');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  return payload;
});

app.addContentTypeParser('application/json', { parseAs: 'string' }, (_request, body, done) => {
  const rawBody = typeof body === 'string' ? body : body.toString('utf8');
  const trimmedBody = rawBody.trim();
  if (trimmedBody.length === 0) {
    done(null, {});
    return;
  }

  try {
    const parsedBody: unknown = JSON.parse(trimmedBody);
    done(null, parsedBody);
  } catch (error: unknown) {
    done(error instanceof Error ? error : new Error('Invalid JSON body'));
  }
});

await app.register(rateLimit, {
  max: config.rateLimitMax,
  timeWindow: config.rateLimitWindow,
  keyGenerator: (request) => {
    const client = request.headers['x-privatechat-client'];
    const clientName = Array.isArray(client) ? client[0] : client;
    return `${request.ip}:${clientName ?? 'unknown'}`;
  }
});

app.setErrorHandler((error: FastifyError | Error, request, reply) => {
  request.log.warn({ err: error, path: request.url.split('?')[0], requestID: request.id }, 'Relay request failed');

  if (error instanceof RelayHttpError) {
    void reply.status(error.statusCode).send({ error: error.message, requestID: request.id });
    return;
  }

  if (error instanceof ZodError) {
    void reply.status(400).send({ error: 'Invalid request', requestID: request.id, details: error.flatten() });
    return;
  }

  if ('statusCode' in error && typeof error.statusCode === 'number' && error.statusCode >= 400 && error.statusCode < 500) {
    void reply.status(error.statusCode).send({ error: error.message, requestID: request.id });
    return;
  }

  const responseBody = config.nodeEnv === 'production'
    ? { error: 'Internal server error', requestID: request.id }
    : { error: 'Internal server error', requestID: request.id, detail: errorMessage(error) };

  void reply.status(500).send(responseBody);
});

const store = config.storeType === 'file'
  ? new FileRelayStore(config.dataDir)
  : new InMemoryRelayStore();

await registerRelayRoutes({
  app,
  config,
  store
});

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error: unknown) {
  app.log.error({ message: errorMessage(error) }, 'Relay startup failed');
  process.exit(1);
}
