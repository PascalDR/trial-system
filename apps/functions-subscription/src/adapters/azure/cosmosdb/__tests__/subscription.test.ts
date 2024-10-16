import { describe, expect, it } from 'vitest';
import * as E from 'fp-ts/lib/Either';
import * as O from 'fp-ts/lib/Option';
import { Database, ErrorResponse } from '@azure/cosmos';
import { makeSubscriptionCosmosContainer } from '../subscription';
import { makeDatabaseMock } from './mocks';
import { aSubscription } from '../../../../domain/__tests__/data';
import { ItemAlreadyExists } from '../../../../domain/errors';

describe('makeSubscriptionCosmosContainer', () => {
  const containerName = 'aContainerName';
  describe('get', () => {
    it('should return the item if found', async () => {
      const mockDB = makeDatabaseMock();
      const { id } = aSubscription;

      mockDB.container('').item.mockReturnValueOnce({
        read: () => Promise.resolve({ resource: aSubscription }),
      });

      const actual = await makeSubscriptionCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).get(aSubscription.id)();

      expect(actual).toStrictEqual(E.right(O.some(aSubscription)));
      expect(mockDB.container('').item).toBeCalledWith(id, id);
    });

    it('should return None if item does not exist', async () => {
      const mockDB = makeDatabaseMock();
      const { id } = aSubscription;

      mockDB.container('').item.mockReturnValueOnce({
        read: () => Promise.resolve({ resource: undefined }),
      });

      const actual = await makeSubscriptionCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).get(aSubscription.id)();

      expect(actual).toStrictEqual(E.right(O.none));
      expect(mockDB.container('').item).toBeCalledWith(id, id);
    });
  });

  describe('insert', () => {
    it('should insert the item if does not already exist', async () => {
      const mockDB = makeDatabaseMock();

      mockDB
        .container('')
        .items.create.mockReturnValueOnce(
          Promise.resolve({ body: aSubscription }),
        );

      const actual = await makeSubscriptionCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).insert(aSubscription)();

      expect(actual).toStrictEqual(E.right(aSubscription));
      expect(mockDB.container('').items.create).toBeCalledWith(aSubscription);
    });

    it('should return ItemAlreadyExists if the item already exists', async () => {
      const mockDB = makeDatabaseMock();
      const error = new ErrorResponse('');
      // eslint-disable-next-line functional/immutable-data
      error.code = 409;

      mockDB.container('').items.create.mockRejectedValueOnce(error);

      const actual = await makeSubscriptionCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).insert(aSubscription)();

      expect(actual).toMatchObject(
        E.left(
          new ItemAlreadyExists(
            `The item already exists; original error body: ${error.body}`,
          ),
        ),
      );
      expect(mockDB.container('').items.create).toBeCalledWith(aSubscription);
    });
  });

  describe('upsert', () => {
    it('should call upsert as expected', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;

      mockDB
        .container('')
        .items.upsert.mockResolvedValueOnce({ resource: aSubscription });

      const actual = await makeSubscriptionCosmosContainer(
        testDB,
        containerName,
      ).upsert(aSubscription)();

      expect(actual).toStrictEqual(E.right(void 0));
      expect(mockDB.container('').items.upsert).toBeCalledWith(aSubscription);
    });

    it('should call upsert and raise an error', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;
      const error = new Error('Oh No!');

      mockDB.container('').items.upsert.mockRejectedValueOnce(error);

      const actual = await makeSubscriptionCosmosContainer(
        testDB,
        containerName,
      ).upsert(aSubscription)();

      expect(actual).toStrictEqual(E.left(error));
      expect(mockDB.container('').items.upsert).toBeCalledWith(aSubscription);
    });
  });
});
