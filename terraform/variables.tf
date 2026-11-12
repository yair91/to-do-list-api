variable "region" {
  type    = string
  default = "us-east-1"
}

variable "proyecto" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "todo-api"
}

variable "repo_url" {
  description = "Repositorio que clona la EC2 al arrancar"
  type        = string
}

variable "app_version" {
  description = "Version inicial que reporta /version. Vacio = main-<commit>"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Correo que recibe las alarmas por SNS"
  type        = string
}

variable "zonas" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "instance_profile" {
  description = "En AWS Academy no se pueden crear roles, se usa el perfil del lab"
  type        = string
  default     = "LabInstanceProfile"
}

variable "ssh_cidrs" {
  description = "IPs que pueden entrar por SSH. Vacio = puerto 22 cerrado"
  type        = list(string)
  default     = []
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_nombre" {
  type    = string
  default = "todo"
}

variable "db_usuario" {
  type    = string
  default = "todo_admin"
}
