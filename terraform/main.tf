terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # el bucket se pasa en terraform init con -backend-config="bucket=..."
  # (lo crea scripts/crear-backend.sh)
  backend "s3" {
    key          = "to-do-list-api/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.proyecto
    }
  }
}

locals {
  namespace = "TodoList"
}

data "aws_caller_identity" "actual" {}

# ---------- red ----------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = var.zonas
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.proyecto}-app"
  description = "API de to-do-list en el puerto 8000"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = length(var.ssh_cidrs) > 0 ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.proyecto}-rds"
  description = "PostgreSQL solo desde la EC2 de la API"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL desde la API"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- key pair ----------

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "app" {
  key_name   = "${var.proyecto}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

# ---------- RDS + Secrets Manager ----------

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_id" "sufijo" {
  byte_length = 3
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.proyecto}-db"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "db" {
  identifier              = "${var.proyecto}-db"
  engine                  = "postgres"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = var.db_nombre
  username                = var.db_usuario
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.proyecto}/rds-${random_id.sufijo.hex}"
  description             = "Credenciales de RDS de to-do-list-api"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.db.address
    port     = aws_db_instance.db.port
    dbname   = var.db_nombre
    username = var.db_usuario
    password = random_password.db.result
  })
}

# ---------- EC2 ----------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.app.key_name
  iam_instance_profile        = var.instance_profile
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url    = var.repo_url
    secret_id   = aws_secretsmanager_secret.db.name
    region      = var.region
    namespace   = local.namespace
    app_version = var.app_version
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = var.proyecto
  }

  # cuando sale una AMI nueva no se recrea la instancia (se perderia la version desplegada)
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_secretsmanager_secret_version.db]
}

# ---------- alertas ----------

resource "aws_sns_topic" "alertas" {
  name = "${var.proyecto}-alertas"
}

resource "aws_sns_topic_subscription" "correo" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  # el ID de la EC2 no se conoce hasta el apply y for_each necesita llaves fijas,
  # asi que la plantilla se arma con un marcador y el ID se pone en las dimensiones
  marcador_instancia = "__INSTANCE_ID__"
  alarmas = {
    for a in jsondecode(templatefile("${path.module}/../alerting/alarms.json", {
      instance_id = local.marcador_instancia
      namespace   = local.namespace
    })) : a.name => a
  }
}

resource "aws_cloudwatch_metric_alarm" "alarmas" {
  for_each = local.alarmas

  alarm_name        = each.value.name
  alarm_description = each.value.description
  namespace         = each.value.namespace
  metric_name       = each.value.metric_name
  dimensions = can(each.value.dimensions) ? {
    for k, v in each.value.dimensions : k => replace(v, local.marcador_instancia, aws_instance.app.id)
  } : null
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = [aws_sns_topic.alertas.arn]
  ok_actions          = [aws_sns_topic.alertas.arn]
}

resource "aws_cloudwatch_dashboard" "app" {
  dashboard_name = var.proyecto
  dashboard_body = templatefile("${path.module}/../alerting/cloudwatch-dashboard.json", {
    instance_id = aws_instance.app.id
    namespace   = local.namespace
    region      = var.region
    account_id  = data.aws_caller_identity.actual.account_id
  })

  depends_on = [aws_cloudwatch_metric_alarm.alarmas]
}
