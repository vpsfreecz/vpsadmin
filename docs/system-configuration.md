# System configuration choices

`SysConfig.register` can constrain a String or Integer setting to an ordered set
of values. Declare the values and labels in code; the database stores the selected
scalar value. There are no choice-specific columns or migrations.

```ruby
SysConfig.register :example, :strategy, String,
                   default: 'manual', nullable: false, min_user_level: 99,
                   choices: { values: {
                     'manual' => 'Manual',
                     'automatic' => VpsAdmin::API::I18n.message(
                       'sysconfig.choices.example.automatic', default: 'Automatic'
                     )
                   } }
```

The `values` map must be nonempty. Keys must match the declared type, and Integer
keys must fit the JavaScript safe-integer range. Labels are nonempty strings or
`HaveAPI::LocalizedMessage` instances with an English default. Localized labels
are resolved for each API response using the request language. Add their keys to
the shared API English and Czech catalogs; clients display the supplied labels.
This is separate from localized setting values: `localized: true` settings cannot
declare choices.

Choice settings accept null by default. Set `nullable: false` to forbid it. A
supplied default must be allowed, and a new nonnullable setting requires a valid
default. Empty-string choices and Integer zero are valid. Null means unset; it
does not imply inheritance or a default unless the setting defines that behavior.

## API and editors

SystemConfig Index, Show and Update return these additional fields:

```json
{
  "choices": [{"value": "manual", "label": "Manual"}],
  "value_nullable": false
}
```

`choices` preserves declaration order and scalar types. Both fields are null for
settings without a choice contract. Older servers can omit them. The existing
Update payload remains `{"system_config":{"value":"manual"}}`; nullable settings
also accept an explicit null. The server validates against its own declaration,
including explicit writes of an already stored unsupported value. Row visibility
and administrator write authorization remain unchanged.

Editors use API labels and stable JSON scalar option tokens. They decode a chosen
token before submitting, so `0`, `"0"`, `""`, `"null"` and null stay distinct. A
nullable setting has an Unset option. An unsupported stored value stays visible
and selected until an operator chooses a supported replacement. Unchanged fields
are not submitted. Malformed choice metadata disables editing rather than
offering an unrestricted input. Settings without choices retain their existing
controls. PHP marks its choice submissions separately so older forms retain the
existing input path; the API remains authoritative when declarations change.

## Registration and rollout

Registration validates declarations and defaults, but does not rewrite or reject
existing unsupported values. Metadata-only saves preserve those values too.
Normal model writes validate new or changed values. Removing choices from the
declaration, including `choices: nil`, removes the process-local contract when
registrations load again. Direct SQL is outside model validation.

Deploy the API declarations before relying on their metadata or validation, and
restart every API and task process that loads them. Older clients can keep using
valid stored scalar values; new editors retain the existing controls when an old
API omits metadata. Complete the backend rollout before relying on enforcement.
Roll back the UI and then the API using the normal deployment procedure. Stored
values do not need conversion, and there is no schema rollback. Keep supported
values compatible throughout a mixed-version rollout.

All incident-policy mode declarations use this mechanism for `observe`, `notify`
and `enforce`. Their meaning is unchanged; see [incident escalation](incident-escalation.md).
Changing a mode does not replay past incidents.
