job "client-proxy" {
  datacenters = ["${aws_az1}", "${aws_az2}"]
  priority    = 80
  node_pool   = "api"

  group "client-proxy" {
    network {
      port "client-proxy" {
        static = 3002
      }

      port "health" {
        static = 3001
      }
    }

    service {
      name = "proxy"
      port = "client-proxy"

      check {
        type     = "http"
        name     = "health"
        path     = "/"
        interval = "3s"
        timeout  = "3s"
        port     = "health"
      }
    }

    update {
      max_parallel        = 1
      canary             = 1
      min_healthy_time   = "10s"
      healthy_deadline   = "30s"
      auto_promote       = true
      progress_deadline  = "24h"
    }

    task "start" {
      driver      = "docker"
      kill_timeout = "24h"
      kill_signal = "SIGTERM"

      resources {
        memory_max = 4096
        memory     = 1024
        cpu        = 1000
      }

      env {
        OTEL_COLLECTOR_GRPC_ENDPOINT = "localhost:4317"
      }

      config {
        network_mode = "host"
        image        = "${account_id}.dkr.ecr.${AWSREGION}.amazonaws.com/e2b-orchestration/client-proxy:latest"      
        ports        = ["client-proxy"]
        args         = ["--port", "3002"]
        auth {
          username = "AWS"
          password = "${ecr_token}"
        }
      }
    }
  }
}