resource "azurerm_cdn_frontdoor_profile" "cdn" {
  name                = "${var.app-name}-${var.environment}-standard"
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "cdn" {
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.cdn.id
  enabled                  = true
  name                     = "${var.app-name}-${var.environment}-afd"
  tags                     = {}
}

resource "azurerm_cdn_frontdoor_origin_group" "api" {
  cdn_frontdoor_profile_id                                  = azurerm_cdn_frontdoor_profile.cdn.id
  name                                                      = "${var.app-name}-${var.environment}-api-group"
  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 0
  session_affinity_enabled                                  = false

  health_probe {
    interval_in_seconds = 100
    path                = var.health-check-path
    protocol            = "Https"
    request_type        = "GET"
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "api" {
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.api.id
  certificate_name_check_enabled = false
  enabled                        = true
  host_name                      = azurerm_linux_web_app.app.default_hostname
  #http_port                      = 80
  https_port         = 443
  name               = "${var.app-name}-${var.environment}-api"
  origin_host_header = azurerm_linux_web_app.app.default_hostname
  priority           = 1
  weight             = 1000
}

resource "azurerm_cdn_frontdoor_route" "api" {
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.cdn.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api.id
  #cdn_frontdoor_origin_group_id = null
  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.api.id
  ]
  enabled                = true
  forwarding_protocol    = "MatchRequest"
  https_redirect_enabled = false
  name                   = "${var.app-name}-${var.environment}-api-route"
  patterns_to_match = [
    var.api-base-path,
  ]
  supported_protocols = [
    "Https",
  ]
}

resource "azurerm_cdn_frontdoor_origin_group" "web" {
  cdn_frontdoor_profile_id                                  = azurerm_cdn_frontdoor_profile.cdn.id
  name                                                      = "${var.app-name}-${var.environment}-web-group"
  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 0
  session_affinity_enabled                                  = false

  health_probe {
    interval_in_seconds = 100
    path                = "/"
    protocol            = "Http"
    request_type        = "HEAD"
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "web" {
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.web.id
  certificate_name_check_enabled = true
  enabled                        = true
  host_name                      = azurerm_storage_account.web.primary_web_host
  http_port                      = 80
  https_port                     = 443
  name                           = "${var.app-name}-${var.environment}-web"
  origin_host_header             = azurerm_storage_account.web.primary_web_host
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_route" "web" {
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.cdn.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id
  cdn_frontdoor_origin_path     = "/"
  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.web.id
  ]
  enabled                = true
  forwarding_protocol    = "MatchRequest"
  https_redirect_enabled = false
  name                   = "${var.app-name}-${var.environment}-route"
  patterns_to_match = [
    "/*",
  ]
  supported_protocols = [
    "Https",
  ]
  cdn_frontdoor_rule_set_ids = [
    azurerm_cdn_frontdoor_rule_set.rule_set_web.id
  ]
}


resource "azurerm_cdn_frontdoor_rule_set" "rule_set_web" {
  name                     = "${var.app-name}${var.environment}rulesetweb"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.cdn.id
}



resource "azurerm_cdn_frontdoor_rule" "rule_web" {
  depends_on = [azurerm_cdn_frontdoor_origin_group.web, azurerm_cdn_frontdoor_origin.web]

  name                      = "${var.app-name}${var.environment}ruleweb"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.rule_set_web.id
  order                     = 1
  behavior_on_match         = "Stop"

  actions {
    route_configuration_override_action {
      cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id
      forwarding_protocol           = "HttpsOnly"
      query_string_caching_behavior = "IgnoreQueryString"
      #query_string_parameters       = ["foo", "clientIp={client_ip}"]
      compression_enabled = true
      cache_behavior      = "OverrideIfOriginMissing"
      cache_duration      = "01:00:00"
    }
  }

  conditions {
    url_filename_condition {
      operator         = "Equal"
      negate_condition = false
      match_values     = ["js", "css", "png", "jpg", "jpeg", "svg", "ico", "woff2"]
      transforms       = ["Lowercase", "RemoveNulls", "Trim"]
    }
  }
}


resource "azurerm_cdn_frontdoor_rule" "rule_web_no_cache_index" {
  name                      = "${var.app-name}${var.environment}nocacheindex"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.rule_set_web.id
  order                     = 2
  behavior_on_match         = "Continue"

  conditions {
    url_path_condition {
      operator         = "Equal"
      match_values     = ["/index.html"]
      negate_condition = false
      transforms       = []
    }
  }

  actions {
    route_configuration_override_action {
      cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id
      forwarding_protocol           = "HttpsOnly"
      compression_enabled           = true
      cache_behavior                = "OverrideIfOriginMissing"
      query_string_caching_behavior = "IgnoreQueryString"
      cache_duration                = "01:00:00"
    }
  }
}
