module github.com/LuisMedinaG/mbgc/services/api

go 1.25

require (
	github.com/LuisMedinaG/mbgc/pkg/shared v0.0.0
	github.com/MicahParks/keyfunc/v3 v3.8.0
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/golang-migrate/migrate/v4 v4.19.1
	github.com/jackc/pgx/v5 v5.7.0
)

require (
	github.com/MicahParks/jwkset v0.11.0 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.1 // indirect
	github.com/lib/pq v1.10.9 // indirect
	github.com/pashagolub/pgxmock/v3 v3.4.0 // indirect
	golang.org/x/crypto v0.45.0 // indirect
	golang.org/x/sync v0.18.0 // indirect
	golang.org/x/text v0.31.0 // indirect
	golang.org/x/time v0.12.0 // indirect
)

replace github.com/LuisMedinaG/mbgc/pkg/shared v0.0.0 => ../../pkg/shared
