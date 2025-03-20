# SeriouslyBroke

A modern web application for tracking and managing personal finances, helping users stay on top of their spending and savings goals. Visit [SeriouslyBroke.com](https://seriouslybroke.com) to get started.

## Features

- User authentication with Devise
- Modern, responsive UI with Tailwind CSS
- Personal finance tracking
- Budget management
- Expense categorization
- Financial goal setting
- Interactive dashboards

## Development

### Prerequisites

- Ruby 3.2.0 or higher
- PostgreSQL 14.0 or higher
- Node.js 18.0.0 or higher

### Local Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/SeriouslyBroke.git
   cd SeriouslyBroke
   ```

2. Install Ruby dependencies:
   ```bash
   bundle install
   ```

3. Install JavaScript dependencies:
   ```bash
   yarn install
   ```

4. Set up the database:
   ```bash
   rails db:create db:migrate
   ```

5. Install and build Tailwind CSS:
   ```bash
   rails tailwindcss:install
   rails tailwindcss:build
   ```

### Starting the Server

The application uses `bin/dev` to run both the Rails server and Tailwind CSS compiler in development mode:

```bash
bin/dev
```

This will start:
- Rails server on http://localhost:3000
- Tailwind CSS compiler in watch mode

### Code Quality

The project uses RuboCop for code linting and style enforcement. To automatically fix style issues:

```bash
bundle exec rubocop -A
```

### Testing

Run the test suite:

```bash
bundle exec rspec
```

## About

SeriouslyBroke is a public web application designed to help users manage their personal finances effectively. While the code is publicly visible, this is not an open-source project. The application is hosted at [SeriouslyBroke.com](https://seriouslybroke.com).

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
