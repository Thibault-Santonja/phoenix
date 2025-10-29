# Portfolio

A Phoenix LiveView application showcasing photography, medieval reenactment, and technical projects. Features a complete admin interface for managing photography albums with database-backed content and passwordless authentication.

## Features

### Photography Management
- **Album Administration**: Create, edit, and manage photography albums
- **Photo Upload**: Drag & drop photo uploads with previews (up to 20 files, 10MB each)
- **Published/Draft Status**: Control album visibility
- **Rich Metadata**: Titles, descriptions, dates, locations, and slugs
- **Public Gallery**: Browse albums by year and type (wedding, music, family, etc.)

### Authentication System
- **Passwordless Login**: Magic link authentication via email
- **Session Management**: Database-backed sessions with 30-day expiry
- **User Profiles**: Manage profile information and active sessions
- **Role-Based Access**: Admin and superadmin roles with middleware protection
- **Session Security**: Individual or bulk session revocation

### Architecture
- **Context-Driven Design**: Separate contexts for Auth and Photography
- **Repository Pattern**: Dedicated repositories for data access
- **LiveView Components**: Modern, reactive UI with Phoenix LiveView
- **Comprehensive Tests**: 202 tests with excellent coverage on business logic
  - Auth Context: 100% coverage
  - Photography Context: 100% coverage
  - Plugs & Controllers: 88-100% coverage

## Setup

### Prerequisites
- Elixir 1.17+ and Erlang/OTP 27+
- PostgreSQL 14+
- Node.js 18+ (for assets)
- libvips 8.x+ (for image processing) - See [libvips setup guide](docs/setup/LOCAL_DEV_LIBVIPS.md)

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   mix setup
   ```

3. Create and migrate the database:
   ```bash
   mix ecto.setup
   ```

4. Create an admin user (development only):
   ```elixir
   # In IEx: iex -S mix
   alias Portfolio.Auth.User
   alias Portfolio.Repo
   
   %User{}
   |> User.registration_changeset(%{email: "admin@example.com", role: "admin"})
   |> Repo.insert!()
   ```

5. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

6. Visit [`localhost:4000`](http://localhost:4000)

### Admin Interface

Access the admin panel at [`localhost:4000/login`](http://localhost:4000/login). Enter your email to receive a magic link for passwordless authentication.

Admin features:
- **Albums**: `/admin/albums` - Manage photography albums
- **Profile**: `/admin/profile` - Update profile and manage sessions

## Development

### Running Tests
```bash
mix test                    # Run all tests
mix test --cover           # Run with coverage report
mix test.watch             # Watch mode (if installed)
```

### Code Quality
```bash
mix credo --strict         # Linting and code analysis
mix format                 # Format code
mix dialyzer              # Type checking (first run builds PLT)
```

### Database
```bash
mix ecto.create           # Create database
mix ecto.migrate          # Run migrations
mix ecto.rollback         # Rollback last migration
mix ecto.reset            # Drop, create, and migrate
```

## Project Structure

```
lib/portfolio/
├── auth/                 # Authentication context
│   ├── user.ex          # User schema
│   ├── magic_link.ex    # Magic link schema
│   ├── user_session.ex  # Session schema
│   └── mailer.ex        # Email sending
├── photography/         # Photography context
│   ├── album.ex        # Album schema
│   ├── photo.ex        # Photo schema
│   └── repositories/   # Data access layer
└── auth.ex             # Auth context API

lib/portfolio_web/
├── live/
│   ├── admin/          # Admin LiveViews
│   │   ├── album_live/     # Album management
│   │   └── profile_live/   # Profile management
│   ├── auth_live/      # Authentication LiveViews
│   └── photography_live/   # Public gallery
├── controllers/
│   └── auth_controller.ex  # Magic link verification
└── plugs/
    └── require_auth.ex     # Authentication middleware

test/
├── portfolio/          # Context tests
└── portfolio_web/      # Web layer tests
```

## Deployment

The application is production-ready with:
- Session-based authentication
- Database connection pooling (via Ecto)
- Asset optimization (Esbuild + Tailwind)
- Health check endpoint
- Telemetry and metrics

See the [Phoenix deployment guide](https://hexdocs.pm/phoenix/deployment.html) for detailed instructions.

## Technology Stack

- **Framework**: Phoenix 1.8+ with LiveView 1.0+
- **Language**: Elixir 1.17
- **Database**: PostgreSQL with Ecto 3.10
- **Authentication**: Custom magic link implementation
- **UI**: Tailwind CSS 3.x with Heroicons
- **Email**: Swoosh with configurable adapters
- **Testing**: ExUnit with 202 test cases

## Documentation

- Architecture documentation: `docs/ARCHITECTURE_ADMIN_ALBUMS.md`
- Development rules: `docs/RULES.md` (not committed)
- API documentation: Run `mix docs` to generate

## Contributing

This is a personal portfolio project. For questions or suggestions, please open an issue.

## License

Copyright © 2025 Thibault San. All rights reserved.
