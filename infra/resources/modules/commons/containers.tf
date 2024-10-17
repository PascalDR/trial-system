resource "azurerm_cosmosdb_sql_container" "subscription" {
  name                  = "subscription"
  resource_group_name   = azurerm_resource_group.data_rg.name
  account_name          = module.cosmosdb_account.name
  database_name         = module.cosmosdb_sql_database_trial.name
  partition_key_path    = "/id"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 10000
  }
}

resource "azurerm_cosmosdb_sql_container" "subscription_history" {
  name                  = "subscription-history"
  resource_group_name   = azurerm_resource_group.data_rg.name
  account_name          = module.cosmosdb_account.name
  database_name         = module.cosmosdb_sql_database_trial.name
  partition_key_path    = "/subscriptionId"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 10000
  }

  indexing_policy {
    included_path {
      path = "/*"
    }

    composite_index {
      index {
        path  = "/subscriptionId"
        order = "Ascending"
      }

      index {
        path  = "/version"
        order = "Descending"
      }
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "activation" {
  name                  = "activation"
  resource_group_name   = azurerm_resource_group.data_rg.name
  account_name          = module.cosmosdb_account.name
  database_name         = module.cosmosdb_sql_database_trial.name
  partition_key_path    = "/trialId"
  partition_key_version = 2

  # A unique key is scoped to a logical partition.
  # Remember also that sparse unique keys are not supported. If some unique path
  # values are missing, they're treated as null values, which take part in the
  # uniqueness constraint. For this reason, there can be only a single item with
  # a null value to satisfy this constraint.
  unique_key {
    paths = ["/userId"]
  }

  autoscale_settings {
    max_throughput = 10000
  }

  indexing_policy {
    included_path {
      path = "/*"
    }

    composite_index {
      index {
        path  = "/trialId"
        order = "Ascending"
      }

      index {
        path  = "/type"
        order = "Ascending"
      }

      index {
        path  = "/state"
        order = "Ascending"
      }

      index {
        path  = "/id"
        order = "Ascending"
      }
    }

    composite_index {
      index {
        path  = "/trialId"
        order = "Ascending"
      }

      index {
        path  = "/type"
        order = "Ascending"
      }

      index {
        path  = "/userId"
        order = "Ascending"
      }
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "leases" {
  name                  = "leases"
  resource_group_name   = azurerm_resource_group.data_rg.name
  account_name          = module.cosmosdb_account.name
  database_name         = module.cosmosdb_sql_database_trial.name
  partition_key_path    = "/id"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 2000
  }

  indexing_policy {
    included_path {
      path = "/*"
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "trial" {
  name                  = "trial"
  resource_group_name   = azurerm_resource_group.data_rg.name
  account_name          = module.cosmosdb_account.name
  database_name         = module.cosmosdb_sql_database_trial.name
  partition_key_path    = "/ownerId"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 10000
  }

  indexing_policy {
    included_path {
      path = "/*"
    }

    composite_index {
      index {
        path  = "/id"
        order = "Ascending"
      }

      index {
        path  = "/ownerId"
        order = "Ascending"
      }
    }
  }
}
