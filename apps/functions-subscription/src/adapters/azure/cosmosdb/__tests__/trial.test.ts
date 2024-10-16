import { describe, expect, it } from 'vitest';
import * as E from 'fp-ts/lib/Either';
import * as O from 'fp-ts/lib/Option';
import { Database, ErrorResponse } from '@azure/cosmos';
import { makeDatabaseMock } from './mocks';
import { aTrial } from '../../../../domain/__tests__/data';
import { ItemAlreadyExists } from '../../../../domain/errors';
import { makeTrialsCosmosContainer } from '../trial';

describe('makeTrialsCosmosContainer', () => {
  const containerName = 'aContainerName';
  describe('get', () => {
    const { id } = aTrial;
    it('should return the item if found', async () => {
      const mockDB = makeDatabaseMock();

      mockDB.container('').item.mockReturnValueOnce({
        read: () => Promise.resolve({ resource: aTrial }),
      });

      const actual = await makeTrialsCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).get(id)();

      expect(actual).toStrictEqual(E.right(O.some(aTrial)));
      expect(mockDB.container('').item).toBeCalledWith(id, id);
    });

    it('should return None if item does not exist', async () => {
      const mockDB = makeDatabaseMock();

      mockDB.container('').item.mockReturnValueOnce({
        read: () => Promise.resolve({ resource: undefined }),
      });

      const actual = await makeTrialsCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).get(id)();

      expect(actual).toStrictEqual(E.right(O.none));
      expect(mockDB.container('').item).toBeCalledWith(id, id);
    });
  });
  describe('insert', () => {
    it('should insert the item if does not already exist', async () => {
      const mockDB = makeDatabaseMock();

      mockDB
        .container('')
        .items.create.mockReturnValueOnce(Promise.resolve({ body: aTrial }));

      const actual = await makeTrialsCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).insert(aTrial)();

      expect(actual).toStrictEqual(E.right(aTrial));
      expect(mockDB.container('').items.create).toBeCalledWith(aTrial);
    });

    it('should return ItemAlreadyExists if the item already exists', async () => {
      const mockDB = makeDatabaseMock();
      const error = new ErrorResponse('');
      // eslint-disable-next-line functional/immutable-data
      error.code = 409;

      mockDB.container('').items.create.mockRejectedValueOnce(error);

      const actual = await makeTrialsCosmosContainer(
        mockDB as unknown as Database,
        containerName,
      ).insert(aTrial)();

      expect(actual).toMatchObject(
        E.left(
          new ItemAlreadyExists(
            `The item already exists; original error body: ${error.body}`,
          ),
        ),
      );
      expect(mockDB.container('').items.create).toBeCalledWith(aTrial);
    });
  });
  describe('upsert', () => {
    it('should call upsert as expected', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;

      mockDB
        .container('')
        .items.upsert.mockResolvedValueOnce({ resource: aTrial });

      const actual = await makeTrialsCosmosContainer(
        testDB,
        containerName,
      ).upsert(aTrial)();

      expect(actual).toStrictEqual(E.right(aTrial));
      expect(mockDB.container('').items.upsert).toBeCalledWith(aTrial);
    });

    it('should call upsert and raise an error', async () => {
      const mockDB = makeDatabaseMock();
      const testDB = mockDB as unknown as Database;
      const error = new Error('Oh No!');

      mockDB.container('').items.upsert.mockRejectedValueOnce(error);

      const actual = await makeTrialsCosmosContainer(
        testDB,
        containerName,
      ).upsert(aTrial)();

      expect(actual).toStrictEqual(E.left(error));
      expect(mockDB.container('').items.upsert).toBeCalledWith(aTrial);
    });
  });
});
