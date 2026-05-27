resource "aws_iam_role" "step_functions_auto_start_stop" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  description           = null
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "StepFunctions-auto-start-stop-${var.app-name}-${var.environment}-role"
  name_prefix           = null
  path                  = "/service-role/"
  permissions_boundary  = null
  tags                  = {}
  tags_all              = {}
}


# 1. マネージドポリシーを作成
resource "aws_iam_policy" "step_functions_auto_start_stop_policy" {
  name = "StepFunctions-auto-start-stop-${var.app-name}-${var.environment}-policy"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "rds:StartDBCluster",
          "ecs:UpdateService",
          "rds:StopDBCluster",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.self.account_id}:instance/*",
          "arn:aws:rds:*:${data.aws_caller_identity.self.account_id}:cluster:*",
          #"arn:aws:ecs:*:${data.aws_caller_identity.self.account_id}:service/*/*"
          "arn:aws:ecs:*:${data.aws_caller_identity.self.account_id}:service/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ],
        Resource = [
          "*"
        ]
        Sid = "id2"
      }

    ]
  })
}

# 2. ロールにアタッチ
resource "aws_iam_role_policy_attachment" "step_functions_auto_start_stop" {
  role       = aws_iam_role.step_functions_auto_start_stop.name
  policy_arn = aws_iam_policy.step_functions_auto_start_stop_policy.arn
}


resource "aws_sfn_state_machine" "auto_stop" {
  definition = jsonencode({
    Comment       = "${var.app-name}-${var.environment}-auto-stop"
    QueryLanguage = "JSONata"
    StartAt       = "UpdateService"
    States = {
      StopDBCluster = {
        Arguments = {
          DbClusterIdentifier = aws_rds_cluster.cluster.cluster_identifier
        }
        Next     = "StopInstances"
        Resource = "arn:aws:states:::aws-sdk:rds:stopDBCluster"
        Type     = "Task"
      }
      StopInstances = {
        Arguments = {
          InstanceIds = [
            aws_instance.bastion.id
          ]
        }
        End      = true
        Resource = "arn:aws:states:::aws-sdk:ec2:stopInstances"
        Type     = "Task"
      }
      UpdateService = {
        Arguments = {
          Cluster      = aws_ecs_cluster.cluster.name
          DesiredCount = 0
          Service      = aws_ecs_service.service.name
        }
        Next     = "StopDBCluster"
        Resource = "arn:aws:states:::aws-sdk:ecs:updateService"
        Type     = "Task"
      }
    }
  })
  name     = "exec-auto-stop-${var.app-name}-${var.environment}"
  region   = data.aws_region.current.region
  role_arn = aws_iam_role.step_functions_auto_start_stop.arn
  tags     = {}
  type     = "STANDARD"
}

resource "aws_sfn_state_machine" "auto_start" {
  definition = jsonencode({
    Comment       = "${var.app-name}-${var.environment}-auto-start"
    QueryLanguage = "JSONata"
    StartAt       = "StartInstances"
    States = {
      StartInstances = {
        Arguments = {
          InstanceIds = [
            aws_instance.bastion.id
          ]
        }
        Next     = "StartDBCluster"
        Resource = "arn:aws:states:::aws-sdk:ec2:startInstances"
        Type     = "Task"
      }
      StartDBCluster = {
        Arguments = {
          DbClusterIdentifier = aws_rds_cluster.cluster.cluster_identifier
        }
        Next     = "WaitForDBCluster"
        Resource = "arn:aws:states:::aws-sdk:rds:startDBCluster"
        Type     = "Task"
      }
      WaitForDBCluster = {
        Seconds = 720
        Next    = "UpdateService"
        Type    = "Wait"
      }
      UpdateService = {
        Arguments = {
          Cluster      = aws_ecs_cluster.cluster.name
          DesiredCount = 1
          Service      = aws_ecs_service.service.name
        }
        End      = true
        Resource = "arn:aws:states:::aws-sdk:ecs:updateService"
        Type     = "Task"
      }
    }
  })
  name     = "exec-auto-start-${var.app-name}-${var.environment}"
  region   = data.aws_region.current.region
  role_arn = aws_iam_role.step_functions_auto_start_stop.arn
  tags     = {}
  type     = "STANDARD"
}

resource "aws_iam_role" "scheduler_step_functions" {
  name = "scheduler-step-functions-${var.app-name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler_step_functions" {
  name = "allow-start-execution"
  role = aws_iam_role.scheduler_step_functions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "states:StartExecution"
        Resource = [
          aws_sfn_state_machine.auto_stop.arn,
          aws_sfn_state_machine.auto_start.arn,
        ]
      }
    ]
  })
}

resource "aws_scheduler_schedule" "auto_stop" {
  name       = "auto-stop-${var.app-name}-${var.environment}"
  group_name = "default"

  schedule_expression          = "cron(0 21 * * ? *)"
  schedule_expression_timezone = "Asia/Tokyo"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.auto_stop.arn
    role_arn = aws_iam_role.scheduler_step_functions.arn

    input = jsonencode({})
  }
}

resource "aws_scheduler_schedule" "auto_start" {
  name       = "auto-start-${var.app-name}-${var.environment}"
  group_name = "default"
  state      = "DISABLED"

  schedule_expression          = "cron(0 7 ? * SAT,SUN *)"
  schedule_expression_timezone = "Asia/Tokyo"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.auto_start.arn
    role_arn = aws_iam_role.scheduler_step_functions.arn

    input = jsonencode({})
  }
}
