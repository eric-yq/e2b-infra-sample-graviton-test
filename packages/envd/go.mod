module github.com/e2b-dev/infra/packages/envd

go 1.24

require (
	connectrpc.com/authn v0.1.0
	connectrpc.com/connect v1.16.2
	connectrpc.com/cors v0.1.0
	github.com/creack/pty v1.1.18
	github.com/e2b-dev/infra/packages/shared v0.0.0
	github.com/e2b-dev/fsnotify v0.0.0-20241216145137-2fe5d32bcb51
	github.com/go-chi/chi/v5 v5.0.12
	github.com/oapi-codegen/oapi-codegen/v2 v2.4.1
	github.com/oapi-codegen/runtime v1.1.1
	github.com/rs/cors v1.11.0
	github.com/rs/zerolog v1.33.0
	google.golang.org/protobuf v1.35.1
)

require (
	github.com/apapsch/go-jsonmerge/v2 v2.0.0 // indirect
	github.com/dchest/uniuri v1.2.0 // indirect
	github.com/dprotaso/go-yit v0.0.0-20220510233725-9ba8df137936 // indirect
	github.com/getkin/kin-openapi latest // indirect
	github.com/go-openapi/jsonpointer v0.21.0 // indirect
	github.com/go-openapi/swag v0.23.0 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/invopop/yaml v0.3.1 // indirect
	github.com/josharian/intern v1.0.0 // indirect
	github.com/mailru/easyjson v0.7.7 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mohae/deepcopy v0.0.0-20170929034955-c48cc78d4826 // indirect
	github.com/perimeterx/marshmallow v1.1.5 // indirect
	github.com/speakeasy-api/openapi-overlay v0.9.0 // indirect
	github.com/vmware-labs/yaml-jsonpath v0.3.2 // indirect
	golang.org/x/mod v0.17.0 // indirect
	golang.org/x/sys v0.27.0 // indirect
	golang.org/x/text v0.20.0 // indirect
	golang.org/x/tools v0.21.1-0.20240508182429-e35e4ccd0d2d // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/e2b-dev/infra/packages/shared v0.0.0 => ../shared
