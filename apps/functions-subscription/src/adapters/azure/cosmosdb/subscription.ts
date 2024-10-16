import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import * as E from 'fp-ts/lib/Either';
import { Database } from '@azure/cosmos';
import {
  SubscriptionCodec,
  SubscriptionReader,
  SubscriptionWriter,
} from '../../../domain/subscription';
import { decodeFromItem } from './decode';
import { cosmosErrorToDomainError } from './errors';

export const makeSubscriptionCosmosContainer = (
  db: Database,
  containerName: string,
): SubscriptionReader & SubscriptionWriter => {
  const container = db.container(containerName);
  return {
    get: (subscriptionId) =>
      pipe(
        TE.tryCatch(
          () => container.item(subscriptionId, subscriptionId).read(),
          E.toError,
        ),
        TE.flatMapEither(decodeFromItem(SubscriptionCodec)),
      ),
    insert: (subscription) =>
      pipe(
        TE.tryCatch(() => container.items.create(subscription), E.toError),
        TE.map(() => subscription),
        TE.mapLeft(cosmosErrorToDomainError),
      ),
    upsert: (subscription) =>
      pipe(
        TE.tryCatch(() => container.items.upsert(subscription), E.toError),
        TE.map(() => void 0),
        TE.mapLeft(cosmosErrorToDomainError),
      ),
  };
};
