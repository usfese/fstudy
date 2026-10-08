export class DomainError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: 400 | 401 | 403 | 404 | 409 | 413 | 415 | 429 | 503 = 400,
  ) {
    super(message);
    this.name = 'DomainError';
  }
}
