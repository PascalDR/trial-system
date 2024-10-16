import { describe, expect, it } from 'vitest';
import * as O from 'fp-ts/lib/Option';
import * as E from 'fp-ts/lib/Either';
import { Database, ErrorResponse } from '@azure/cosmos';
import { makeDatabaseMock } from './mocks';
import { aSubscriptionHistory } from '../../../../domain/__tests__/data';
import { makeSubscriptionHistoryCosmosContainer } from '../subscription-history';
import { ItemAlreadyExists } from '../../../../domain/errors';

describe('makeSubscriptionHistoryCosmosContainer', () => {
  const containerName = 'aContainerName';
  describe('insert', () => {
    it('should insert the item if does not already exist', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;

      mockDB
        .container('')
        .items.create.mockResolvedValueOnce({ body: aSubscriptionHistory });

      const actual = await makeSubscriptionHistoryCosmosContainer(
        testDB,
        containerName,
      ).insert(aSubscriptionHistory)();

      expect(actual).toStrictEqual(E.right(aSubscriptionHistory));
      expect(mockDB.container('').items.create).toBeCalledWith(
        aSubscriptionHistory,
      );
    });

    it('should return ItemAlreadyExists if the item already exists', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;
      const error = new ErrorResponse('');
      // eslint-disable-next-line functional/immutable-data
      error.code = 409;

      mockDB.container('').items.create.mockRejectedValueOnce(error);

      const actual = await makeSubscriptionHistoryCosmosContainer(
        testDB,
        containerName,
      ).insert(aSubscriptionHistory)();

      expect(actual).toMatchObject(
        E.left(
          new ItemAlreadyExists(
            `The item already exists; original error body: ${error.body}`,
          ),
        ),
      );
      expect(mockDB.container('').items.create).toBeCalledWith(
        aSubscriptionHistory,
      );
    });
  });

  describe('getLatest', () => {
    it('should run the query to get latest version and returns the item', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;
      const { subscriptionId } = aSubscriptionHistory;

      mockDB.container('').items.query.mockReturnValueOnce({
        fetchAll: () => Promise.resolve({ resources: [aSubscriptionHistory] }),
      });

      const actual = await makeSubscriptionHistoryCosmosContainer(
        testDB,
        containerName,
      ).getLatest({ subscriptionId })();

      expect(actual).toStrictEqual(E.right(O.some(aSubscriptionHistory)));
      expect(mockDB.container('').items.query).toBeCalledWith({
        query:
          'SELECT * FROM c WHERE c.subscriptionId = @sId ORDER BY c.version DESC OFFSET 0 LIMIT 1',
        parameters: [
          {
            name: '@sId',
            value: subscriptionId,
          },
        ],
      });
    });

    it('should return none if query returns empty array', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;
      const { subscriptionId } = aSubscriptionHistory;

      mockDB.container('').items.query.mockReturnValueOnce({
        fetchAll: () => Promise.resolve({ resources: [] }),
      });

      const actual = await makeSubscriptionHistoryCosmosContainer(
        testDB,
        containerName,
      ).getLatest({ subscriptionId })();

      expect(actual).toStrictEqual(E.right(O.none));
    });
  });
});
