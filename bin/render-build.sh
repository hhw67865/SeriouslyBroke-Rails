#!/usr/bin/env bash

# Exit on error
set -o errexit

bundle install
yarn install
bin/rails assets:precompile
bin/rails assets:clean
bin/rails tailwindcss:install
bin/rails tailwindcss:build

bin/rails db:migrate