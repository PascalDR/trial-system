import * as t from 'io-ts';
import { NonEmptyString } from '@pagopa/ts-commons/lib/strings';
import { parseConfigOrThrow } from './parse-config';
import { BulkOperationType, CosmosClient } from '@azure/cosmos';

const EnvsCodec = t.type({
  COSMOS_CONNECTION_STRING: NonEmptyString,
  COSMOS_DATABASE_NAME: NonEmptyString,
  FROM_CONTAINER_NAME: NonEmptyString,
  TO_CONTAINER_NAME: NonEmptyString,
  WALLET_TRIAL_IDS: NonEmptyString,
  WALLET_OWNER_ID: NonEmptyString,
  DEFAULT_OWNER_ID: NonEmptyString,
});

const config = parseConfigOrThrow(EnvsCodec, process.env);

const cosmosDB = new CosmosClient(config.COSMOS_CONNECTION_STRING);

const fromCosmosContainer = cosmosDB
  .database(config.COSMOS_DATABASE_NAME)
  .container(config.FROM_CONTAINER_NAME);
const toCosmosContainer = cosmosDB
  .database(config.COSMOS_DATABASE_NAME)
  .container(config.TO_CONTAINER_NAME);
const walletTrials = config.WALLET_TRIAL_IDS.split(',');

const runTrialMigration = async () => {
  console.log(
    `Migrate all items from '${fromCosmosContainer.id}' to '${toCosmosContainer.id}'\n`,
  );

  const items = fromCosmosContainer.items.query<{
    readonly id: string;
    readonly name: string;
    readonly ownerId?: string;
  }>({
    query: `SELECT * FROM c`,
  });

  // eslint-disable-next-line functional/no-loop-statements
  for await (const { resources: elems } of items.getAsyncIterator()) {
    const operations = elems
      .map((elem) => {
        if (elem.ownerId) {
          // Do not change the item, if it has the `ownerId` property set
          console.log(
            `Trial ${elem.id} has already to an owner (${elem.ownerId}). Do not change it.`,
          );
          return elem;
        } else if (walletTrials.includes(elem.id)) {
          console.log(
            `Trial ${elem.name} (${elem.id}) is going to be linked to the Wallet Owner`,
          );
          return { ...elem, ownerId: config.WALLET_OWNER_ID };
        } else {
          console.log(
            `Trial ${elem.name} (${elem.id}) is going to be linked to the Default Owner`,
          );
          return { ...elem, ownerId: config.DEFAULT_OWNER_ID };
        }
      })
      .map((migrated) => ({
        operationType: BulkOperationType.Create,
        resourceBody: migrated,
      }));

    const result = await toCosmosContainer.items.bulk(operations, {
      continueOnError: true,
    });

    console.log(
      'Operations status code:',
      JSON.stringify(
        result.map(({ statusCode, resourceBody }) => ({
          statusCode,
          id: resourceBody?.id,
        })),
        null,
        2,
      ),
    );
  }

  console.log('\nDone');
};

runTrialMigration();
