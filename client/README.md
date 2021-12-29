# vpsAdmin client

vpsAdmin client is a Ruby CLI and client library for vpsAdmin API. It is based
on [haveapi-client](https://github.com/vpsfreecz/haveapi/tree/master/clients/ruby).

vpsAdmin client extends `haveapi-client` with several command-line operations
specific to vpsAdmin, including:

- VPS remote console
- Snapshot downloads, either ZFS streams or tar archives
- Automated utility for local backups using ZFS
- Live IP traffic monitor

## Installation

Add this line to your application's Gemfile:

    gem 'vpsadmin-client'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install vpsadmin-client

## Usage
See
[haveapi-client](https://github.com/vpsfreecz/haveapi/tree/master/clients/ruby)
for usage information.
