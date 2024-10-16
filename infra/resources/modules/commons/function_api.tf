#
# Function app definition
#

locals {
  func_api_app_settings = {
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

    SUBSCRIPTION_HISTORY_CONSUMER                        = "off"
    SUBSCRIPTION_HISTORY_COSMOSDB_CONTAINER_NAME         = azurerm_cosmosdb_sql_container.subscription_history.name
    SubscriptionHistoryCosmosConnection__accountEndpoint = module.cosmosdb_account.endpoint

    SUBSCRIPTION_REQUEST_CONSUMER                                  = "off"
    SUBSCRIPTION_REQUEST_EVENTHUB_NAME                             = local.subscription_request_eventhub_name
    SubscriptionRequestEventHubConnection__fullyQualifiedNamespace = "${module.event_hub.name}.servicebus.windows.net"

    ACTIVATION_CONSUMER                                   = "off"
    ACTIVATION_MAX_FETCH_SIZE                             = "999"
    ACTIVATIONS_COSMOSDB_CONTAINER_NAME                   = azurerm_cosmosdb_sql_container.activation.name
    ActivationConsumerCosmosDBConnection__accountEndpoint = module.cosmosdb_account.endpoint

    EVENTS_PRODUCER              = "off"
    EVENTS_SERVICEBUS_TOPIC_NAME = azurerm_servicebus_topic.events.name

    TRIAL_CONSUMER                          = "off"
    TRIALS_COSMOSDB_CONTAINER_NAME          = azurerm_cosmosdb_sql_container.trials.name
    TrialsCosmosConnection__accountEndpoint = module.cosmosdb_account.endpoint

    AI_CONNECTION_STRING = azurerm_application_insights.ai.connection_string

  }
}

resource "azurerm_resource_group" "api_rg" {
  name     = "${local.project}-api-rg-01"
  location = var.location

  tags = var.tags
}

module "func_api" {
  source = "github.com/pagopa/dx//infra/modules/azure_function_app?ref=main"

  environment = {
    prefix          = var.prefix
    env_short       = var.env_short
    location        = var.location
    app_name        = "api"
    instance_number = "01"
  }

  resource_group_name = azurerm_resource_group.api_rg.name

  health_check_path = "/info"

  application_insights_connection_string   = azurerm_application_insights.ai.connection_string
  application_insights_sampling_percentage = 5

  app_settings = merge(
    local.func_api_app_settings,
    {},
  )

  slot_app_settings = merge(
    local.func_api_app_settings,
    {},
  )

  subnet_cidr   = var.cidr_subnet_func_api
  subnet_pep_id = module.pendpoints_snet.id
  virtual_network = {
    name                = azurerm_virtual_network.vnet.name
    resource_group_name = azurerm_resource_group.net_rg.name
  }
  private_dns_zone_resource_group_name = azurerm_resource_group.net_rg.name

  tags = var.tags
}

resource "azurerm_role_assignment" "evh_subs_publisher" {
  scope                = module.event_hub.hub_ids[local.subscription_request_eventhub_name]
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = module.func_api.function_app.function_app.principal_id
}

# Enables the subs_fn to read and write to cosmosdb
resource "azurerm_cosmosdb_sql_role_assignment" "subs_fn_to_cosmos_db" {
  scope               = "${module.cosmosdb_account.id}/dbs/${module.cosmosdb_sql_database_trial.name}"
  resource_group_name = azurerm_resource_group.data_rg.name
  account_name        = module.cosmosdb_account.name
  role_definition_id  = "${module.cosmosdb_account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.func_api.function_app.function_app.principal_id
}

resource "azurerm_role_assignment" "evh_subs_publisher_staging" {
  scope                = module.event_hub.hub_ids[local.subscription_request_eventhub_name]
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = module.func_api.function_app.function_app.slot.principal_id
}

# Enables the subs_fn_staging to read and write to cosmosdb
resource "azurerm_cosmosdb_sql_role_assignment" "subs_fn_staging_to_cosmos_db" {
  scope               = "${module.cosmosdb_account.id}/dbs/${module.cosmosdb_sql_database_trial.name}"
  resource_group_name = azurerm_resource_group.data_rg.name
  account_name        = module.cosmosdb_account.name
  role_definition_id  = "${module.cosmosdb_account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.func_api.function_app.function_app.slot.principal_id
}

module "function_apis_autoscaler" {
  source = "github.com/pagopa/dx//infra/modules/azure_app_service_plan_autoscaler?ref=main"

  resource_group_name = azurerm_resource_group.api_rg.name
  target_service = {
    function_app_name = module.func_api.function_app.function_app.name
  }

  scheduler = {
    normal_load = {
      default = 4
      minimum = 4
    }
    low_load = {
      default = 3
      minimum = 3
      name    = "night"
      start = {
        hour    = 22
        minutes = 0
      }
      end = {
        hour    = 6
        minutes = 0
      }
    }
    maximum = 30
  }

  scale_metrics = {
    requests = {
      upper_threshold           = 5000
      lower_threshold           = 1000
      increase_by               = 2
      decrease_by               = 2
      statistic_increase        = "Max"
      statistic_decrease        = "Max"
      time_aggregation_increase = "Maximum"
      time_aggregation_decrease = "Maximum"
    },
    cpu = {
      upper_threshold           = 60
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

resource "azurerm_monitor_metric_alert" "func_api_health_check" {

  name                = "[${module.func_api.function_app.function_app.name}] Health Check Failed"
  resource_group_name = module.func_api.function_app.resource_group_name
  scopes              = [module.func_api.function_app.function_app.id]
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
