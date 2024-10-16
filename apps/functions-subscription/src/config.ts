import * as t from 'io-ts';
import * as PR from 'io-ts/PathReporter';
import { pipe } from 'fp-ts/lib/function';
import * as E from 'fp-ts/lib/Either';
import { NonEmptyString } from '@pagopa/ts-commons/lib/strings';
import {
  NumberFromString,
  WithinRangeInteger,
} from '@pagopa/ts-commons/lib/numbers';

type OnOrOff = 'on' | 'off';

const OnOrOffCodec = t.keyof<{
  readonly [K in OnOrOff]: unknown;
}>({
  on: null,
  off: null,
});

export interface Config {
  readonly subscriptionHistory: {
    readonly consumer: OnOrOff;
  };
  readonly subscriptionRequest: {
    readonly consumer: OnOrOff;
  };
  readonly activations: {
    readonly consumer: OnOrOff;
    readonly maxFetchSize: number;
  };
  readonly events: {
    readonly producer: OnOrOff;
  };
  readonly trials: {
    readonly consumer: OnOrOff;
  };
  readonly servicebus: {
    readonly namespace: string;
    readonly names: {
      readonly event: string;
    };
    readonly resourceGroup: string;
    readonly location: string;
  };
  readonly eventhubs: {
    readonly namespace: string;
    readonly names: {
      readonly subscriptionRequest: string;
    };
  };
  readonly cosmosdb: {
    readonly endpoint: string;
    readonly databaseName: string;
    readonly containersNames: {
      readonly leases: string;
      readonly subscriptionHistory: string;
      readonly activations: string;
      readonly trials: string;
      readonly subscription: string;
    };
  };
  readonly azure: {
    readonly subscriptionId: string;
  };
  readonly applicationInsights: {
    readonly connectionString: string;
    readonly samplingPercentage?: number;
  };
}

const EnvsCodec = t.type({
  COSMOSDB_ENDPOINT: NonEmptyString,
  COSMOSDB_DATABASE_NAME: NonEmptyString,
  EVENTHUB_NAMESPACE: NonEmptyString,
  SERVICEBUS_NAMESPACE: NonEmptyString,
  LEASES_COSMOSDB_CONTAINER_NAME: NonEmptyString,
  SUBSCRIPTION_COSMOSDB_CONTAINER_NAME: NonEmptyString,
  SUBSCRIPTION_REQUEST_CONSUMER: OnOrOffCodec,
  SUBSCRIPTION_REQUEST_EVENTHUB_NAME: NonEmptyString,
  SUBSCRIPTION_HISTORY_CONSUMER: OnOrOffCodec,
  SUBSCRIPTION_HISTORY_COSMOSDB_CONTAINER_NAME: NonEmptyString,
  ACTIVATION_CONSUMER: OnOrOffCodec,
  ACTIVATION_MAX_FETCH_SIZE: NumberFromString.pipe(WithinRangeInteger(1, 1000)),
  ACTIVATIONS_COSMOSDB_CONTAINER_NAME: NonEmptyString,
  EVENTS_PRODUCER: OnOrOffCodec,
  EVENTS_SERVICEBUS_TOPIC_NAME: NonEmptyString,
  TRIAL_CONSUMER: OnOrOffCodec,
  TRIALS_COSMOSDB_CONTAINER_NAME: NonEmptyString,
  SUBSCRIPTION_ID: NonEmptyString,
  SERVICE_BUS_RESOURCE_GROUP_NAME: NonEmptyString,
  SERVICE_BUS_LOCATION: NonEmptyString,
  ActivationConsumerCosmosDBConnection__accountEndpoint: NonEmptyString,
  SubscriptionHistoryCosmosConnection__accountEndpoint: NonEmptyString,
  TrialsCosmosConnection__accountEndpoint: NonEmptyString,
  SubscriptionRequestEventHubConnection__fullyQualifiedNamespace:
    NonEmptyString,
  AI_CONNECTION_STRING: NonEmptyString,
  AI_SAMPLING_PERCENTAGE: t.union([NumberFromString, t.undefined]),
});

export const parseConfig = (
  envs: Record<string, undefined | string>,
): E.Either<string, Config> =>
  pipe(
    EnvsCodec.decode(envs),
    E.bimap(
      (errors) => PR.failure(errors).join('\n'),
      (envs) => ({
        subscriptionHistory: {
          consumer: envs.SUBSCRIPTION_HISTORY_CONSUMER,
        },
        subscriptionRequest: {
          consumer: envs.SUBSCRIPTION_REQUEST_CONSUMER,
        },
        activations: {
          consumer: envs.ACTIVATION_CONSUMER,
          maxFetchSize: envs.ACTIVATION_MAX_FETCH_SIZE,
        },
        events: {
          producer: envs.EVENTS_PRODUCER,
        },
        trials: {
          consumer: envs.TRIAL_CONSUMER,
        },
        servicebus: {
          namespace: envs.SERVICEBUS_NAMESPACE,
          names: {
            event: envs.EVENTS_SERVICEBUS_TOPIC_NAME,
          },
          resourceGroup: envs.SERVICE_BUS_RESOURCE_GROUP_NAME,
          location: envs.SERVICE_BUS_LOCATION,
        },
        eventhubs: {
          namespace: envs.EVENTHUB_NAMESPACE,
          names: {
            subscriptionRequest: envs.SUBSCRIPTION_REQUEST_EVENTHUB_NAME,
          },
        },
        cosmosdb: {
          endpoint: envs.COSMOSDB_ENDPOINT,
          databaseName: envs.COSMOSDB_DATABASE_NAME,
          containersNames: {
            leases: envs.LEASES_COSMOSDB_CONTAINER_NAME,
            subscriptionHistory:
              envs.SUBSCRIPTION_HISTORY_COSMOSDB_CONTAINER_NAME,
            activations: envs.ACTIVATIONS_COSMOSDB_CONTAINER_NAME,
            trials: envs.TRIALS_COSMOSDB_CONTAINER_NAME,
            subscription: envs.SUBSCRIPTION_COSMOSDB_CONTAINER_NAME,
          },
        },
        azure: {
          subscriptionId: envs.SUBSCRIPTION_ID,
        },
        applicationInsights: {
          connectionString: envs.AI_CONNECTION_STRING,
          samplingPercentage: envs.AI_SAMPLING_PERCENTAGE,
        },
      }),
    ),
  );
