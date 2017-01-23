vpsAdmin Requests
=================

This vpsAdmin plugin enables users to send requests for registration and
changes of personal information. Received requests are sent to the administrators
for approval.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory, then
setup the database:

    $ rake vpsadmin:plugins:migrate PLUGIN=requests

This plugin requires some mail templates to be installed in order to work.
Examples of such templates are in subdirectory `mail_templates/`. Use
[vpsadmin-mail-templates](https://github.com/vpsfreecz/vpsadmin-mail-templates)
to install them.

## Usage
This plugin defines two new API resources: `UserRequest.Registration` and
`UserRequest.Change`.

Mail templates are searched for in the following order:

- Requests
  - `request_create_<user role>_<request type>`
  - `request_create_<user role>`

- Resolve (approval or denial)
  - `request_resolve_<user role>_<request type>_<request state>`
  - `request_resolve_<user role>_<request type>`
  - `request_resolve_<user role>_<request state>`
  - `request_resolve_<user role>`

Where

- user role is `user` or `admin`
- request type is `registration` or `change`
- request state is one of `approved`, `denied` and `ignored`

The first template that exists for `User` and `Admin` is used. If no templates
are found, no e-mails are sent.
