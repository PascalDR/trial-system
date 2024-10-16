import { pipe } from 'fp-ts/lib/function';
import * as E from 'fp-ts/lib/Either';
import * as RA from 'fp-ts/lib/ReadonlyArray';
import * as TE from 'fp-ts/lib/TaskEither';
import { Database } from '@azure/cosmos';
import {
  SubscriptionHistoryCodec,
  SubscriptionHistoryReader,
  SubscriptionHistoryWriter,
} from '../../../domain/subscription-history';
import { cosmosErrorToDomainError } from './errors';
import { decodeFromFeed } from './decode';

export const makeSubscriptionHistoryCosmosContainer = (
  db: Database,
  containerName: string,
): SubscriptionHistoryReader & SubscriptionHistoryWriter => {
  const container = db.container(containerName);
  return {
    getLatest: ({ subscriptionId }) =>
      pipe(
        TE.tryCatch(
          () =>
            container.items
              .query({
                query:
                  'SELECT * FROM c WHERE c.subscriptionId = @sId ORDER BY c.version DESC OFFSET 0 LIMIT 1',
                parameters: [
                  {
                    name: '@sId',
                    value: subscriptionId,
                  },
                ],
              })
              .fetchAll(),
          E.toError,
        ),
        TE.flatMapEither(decodeFromFeed(SubscriptionHistoryCodec)),
        TE.mapBoth(cosmosErrorToDomainError, RA.head),
      ),
    insert: (subscriptionHistory) =>
      pipe(
        TE.tryCatch(
          () => container.items.create(subscriptionHistory),
          E.toError,
        ),
        TE.mapBoth(cosmosErrorToDomainError, () => subscriptionHistory),
      ),
  };
};
