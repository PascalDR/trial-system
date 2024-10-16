#
# Function app definition
#

locals {
  consumers_app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "node"
    FUNCTIONS_WORKER_PROCESS_COUNT = "4"
    NODE_ENV                       = "production"

    // Keepalive fields are all optionals
    FETCH_KEEPALIVE_ENABLED             = "true"
    FETCH_KEEPALIVE_SOCKET_ACTIVE_TTL   = "110000"
    FETCH_KEEPALIVE_MAX_SOCKETS         = "40"
    FETCH_KEEPALIVE_MAX_FREE_SOCKETS    = "10"
    FETCH_KEEPALIVE_FREE_SOCKET_TIMEOUT = "30000"
    FETCH_KEEPALIVE_TIMEOUT             = "60000"

    COSMOSDB_ENDPOINT               = module.cosmosdb_account.endpoint
    COSMOSDB_DATABASE_NAME          = module.cosmosdb_sql_database_trial.name
    EVENTHUB_NAMESPACE              = module.event_hub.name
    SERVICEBUS_NAMESPACE            = azurerm_servicebus_namespace.main.name
    SERVICE_BUS_RESOURCE_GROUP_NAME = azurerm_servicebus_namespace.main.resource_group_name
    SERVICE_BUS_LOCATION            = azurerm_servicebus_namespace.main.location

    SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id

    LEASES_COSMOSDB_CONTAINER_NAME = azurerm_cosmosdb_sql_container.leases.name

    SUBSCRIPTION_COSMOSDB_CONTAINER_NAME = azurerm_cosmosdb_sql_container.subscription.name

    SUBSCRIPTION_HISTORY_CONSUMER                        = "on"
    SUBSCRIPTION_HISTORY_COSMOSDB_CONTAINER_NAME         = azurerm_cosmosdb_sql_container.subscription_history.name
    SubscriptionHistoryCosmosConnection__accountEndpoint = module.cosmosdb_account.endpoint

    SUBSCRIPTION_REQUEST_CONSUMER                                  = "on"
    SUBSCRIPTION_REQUEST_EVENTHUB_NAME                             = local.subscription_request_eventhub_name
    SubscriptionRequestEventHubConnection__fullyQualifiedNamespace = "${module.event_hub.name}.servicebus.windows.net"

    ACTIVATION_CONSUMER                                   = "on"
    ACTIVATION_MAX_FETCH_SIZE                             = "999"
    ACTIVATIONS_COSMOSDB_CONTAINER_NAME                   = azurerm_cosmosdb_sql_container.activation.name
    ActivationConsumerCosmosDBConnection__accountEndpoint = module.cosmosdb_account.endpoint

    EVENTS_PRODUCER              = "on"
    EVENTS_SERVICEBUS_TOPIC_NAME = azurerm_servicebus_topic.events.name

    TRIAL_CONSUMER                          = "on"
    TRIALS_COSMOSDB_CONTAINER_NAME          = azurerm_cosmosdb_sql_container.trials.name
    TrialsCosmosConnection__accountEndpoint = module.cosmosdb_account.endpoint

    AI_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
  }
}

resource "azurerm_resource_group" "consumer_rg" {
  name     = "${local.project}-consumers-rg-01"
  location = var.location

  tags = var.tags
}

module "func_consumers" {
  source = "github.com/pagopa/dx//infra/modules/azure_function_app?ref=main"

  environment = {
    prefix          = var.prefix
    env_short       = var.env_short
    location        = var.location
    app_name        = "consumers"
    instance_number = "01"
  }

  resource_group_name = azurerm_resource_group.consumer_rg.name

  health_check_path = "/info"

  application_insights_connection_string   = azurerm_application_insights.ai.connection_string
  application_insights_sampling_percentage = 5

  app_settings = merge(
    local.consumers_app_settings,
    {},
  )

  slot_app_settings = merge(
    local.consumers_app_settings,
    {
      // Disable consumers on staging slot
      SUBSCRIPTION_HISTORY_CONSUMER = "off"
      SUBSCRIPTION_REQUEST_CONSUMER = "off"
      ACTIVATION_CONSUMER           = "off"
      EVENTS_PRODUCER               = "off"
      TRIAL_CONSUMER                = "off"
    },
  )

  subnet_cidr   = var.cidr_subnet_func_consumptions
  subnet_pep_id = module.pendpoints_snet.id
  virtual_network = {
    name                = azurerm_virtual_network.vnet.name
    resource_group_name = azurerm_resource_group.net_rg.name
  }
  private_dns_zone_resource_group_name = azurerm_resource_group.net_rg.name

  tags = var.tags
}

# Enables the consumers_fn to write on service-bus topic
resource "azurerm_role_assignment" "subs_asyn_write_to_sbt" {
  scope                = azurerm_servicebus_topic.events.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn to read from the event-hub
resource "azurerm_role_assignment" "subs_asyn_receive_from_evh" {
  scope                = module.event_hub.hub_ids[local.subscription_request_eventhub_name]
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = module.func_consumers.function_app.function_app.principal_id
}

# Enables the subs_fn to read and write to cosmosdb
resource "azurerm_cosmosdb_sql_role_assignment" "subs_async_fn_to_cosmos_db" {
  scope               = "${module.cosmosdb_account.id}/dbs/${module.cosmosdb_sql_database_trial.name}"
  resource_group_name = azurerm_resource_group.data_rg.name
  account_name        = module.cosmosdb_account.name
  role_definition_id  = "${module.cosmosdb_account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn to create user assigned identities in a resource group
resource "azurerm_role_definition" "subs_asyn_create_user_assigned_identity" {
  name  = "Create User Assigned Identity"
  scope = azurerm_resource_group.data_rg.id

  permissions {
    actions = ["Microsoft.ManagedIdentity/userAssignedIdentities/write"]
  }
}

resource "azurerm_role_assignment" "subs_asyn_create_user_assigned_identity" {
  scope              = azurerm_role_definition.subs_asyn_create_user_assigned_identity.scope
  role_definition_id = azurerm_role_definition.subs_asyn_create_user_assigned_identity.role_definition_resource_id
  principal_id       = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn to create queues in the service bus' namespace
resource "azurerm_role_definition" "subs_asyn_create_queue" {
  name  = "Service Bus Create Queue"
  scope = azurerm_servicebus_namespace.main.id

  permissions {
    actions = ["Microsoft.ServiceBus/namespaces/queues/write"]
  }
}

resource "azurerm_role_assignment" "subs_asyn_create_queue" {
  scope              = azurerm_role_definition.subs_asyn_create_queue.scope
  role_definition_id = azurerm_role_definition.subs_asyn_create_queue.role_definition_resource_id
  principal_id       = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn to create topic subscriptions
resource "azurerm_role_definition" "subs_asyn_create_subscription" {
  name  = "Service Bus Create Subscription"
  scope = azurerm_servicebus_topic.events.id

  permissions {
    actions = [
      "Microsoft.ServiceBus/namespaces/topics/subscriptions/write",
    ]
  }
}

resource "azurerm_role_assignment" "subs_asyn_create_subscription" {
  scope              = azurerm_role_definition.subs_asyn_create_subscription.scope
  role_definition_id = azurerm_role_definition.subs_asyn_create_subscription.role_definition_resource_id
  principal_id       = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn to create filters on topic subscriptions
resource "azurerm_role_definition" "subs_asyn_create_filter_rule" {
  name  = "Service Bus Create Filter Rule"
  scope = azurerm_role_definition.subs_asyn_create_subscription.scope

  permissions {
    actions = [
      "Microsoft.ServiceBus/namespaces/topics/subscriptions/rules/write"
    ]
  }
}

resource "azurerm_role_assignment" "subs_asyn_create_filter_rule" {
  scope              = azurerm_role_definition.subs_asyn_create_filter_rule.scope
  role_definition_id = azurerm_role_definition.subs_asyn_create_filter_rule.role_definition_resource_id
  principal_id       = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn to create role assignments
resource "azurerm_role_definition" "subs_asyn_create_role_assignment" {
  name  = "Service Bus Create Role Assignment"
  scope = azurerm_role_definition.subs_asyn_create_queue.scope

  permissions {
    actions = ["Microsoft.Authorization/roleAssignments/write"]
  }
}

# Enables the consumers_fn to create a filter rule
resource "azurerm_role_assignment" "subs_asyn_create_role_assignment" {
  scope              = azurerm_role_definition.subs_asyn_create_role_assignment.scope
  role_definition_id = azurerm_role_definition.subs_asyn_create_role_assignment.role_definition_resource_id
  principal_id       = module.func_consumers.function_app.function_app.principal_id
}

# Enables the consumers_fn_staging to write on service-bus topic
resource "azurerm_role_assignment" "subs_asyn_staging_write_to_sbt" {
  scope                = azurerm_servicebus_topic.events.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = module.func_consumers.function_app.function_app.slot.principal_id
}

# Enables the consumers_fn_staging to read from the event-hub
resource "azurerm_role_assignment" "subs_asyn_staging_receive_from_evh" {
  scope                = module.event_hub.hub_ids[local.subscription_request_eventhub_name]
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = module.func_consumers.function_app.function_app.slot.principal_id
}

# Enables the subs_fn to read and write to cosmosdb
resource "azurerm_cosmosdb_sql_role_assignment" "subs_async_fn_staging_to_cosmos_db" {
  scope               = "${module.cosmosdb_account.id}/dbs/${module.cosmosdb_sql_database_trial.name}"
  resource_group_name = azurerm_resource_group.data_rg.name
  account_name        = module.cosmosdb_account.name
  role_definition_id  = "${module.cosmosdb_account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.func_consumers.function_app.function_app.slot.principal_id
}

module "function_consumptions_autoscaler" {
  source = "github.com/pagopa/dx//infra/modules/azure_app_service_plan_autoscaler?ref=main"

  resource_group_name = azurerm_resource_group.consumer_rg.name
  target_service = {
    function_app_name = module.func_consumers.function_app.function_app.name
  }

  scheduler = {
    normal_load = {
      default = 3
      minimum = 3
    }
    maximum = 30
  }

  scale_metrics = {
    cpu = {
      upper_threshold           = 40
      lower_threshold           = 20
      increase_by               = 2
      decrease_by               = 2
      statistic_increase        = "Max"
      statistic_decrease        = "Max"
      time_aggregation_increase = "Maximum"
      time_aggregation_decrease = "Maximum"
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "func_consumers_health_check" {

  name                = "[${module.func_consumers.function_app.function_app.name}] Health Check Failed"
  resource_group_name = module.func_consumers.function_app.resource_group_name
  scopes              = [module.func_consumers.function_app.function_app.id]
  description         = "Function availability is under threshold level. Runbook: -"
  severity            = 1
  frequency           = "PT5M"
  auto_mitigate       = false
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 50
  }

  action {
    action_group_id    = azurerm_monitor_action_group.error_action_group.id
    webhook_properties = {}
  }
}
