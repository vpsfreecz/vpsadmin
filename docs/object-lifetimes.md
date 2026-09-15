# Object lifetimes

Object lifetimes define how resources become unavailable and are eventually
removed. Users and VPSes use the full set of states; other models can choose
a subset. For example, datasets and snapshot downloads use `active` and
`deleted`.

## States

| State | Meaning |
| --- | --- |
| `active` | The object is available for normal use. |
| `suspended` | Normal use is blocked; the resource still exists. |
| `soft_delete` | The object is retained for possible revival but excluded from normal active-resource listings. |
| `hard_delete` | The managed resource has been removed; its database record remains for record keeping. Revival is no longer allowed. |
| `deleted` | The final removal step deletes the object's database record. |

The specific effects and API visibility depend on the model and resource.
Deleting an object does not imply that every external log or historical record
has disappeared.

## State transitions

Models include `VpsAdmin::API::Lifetimes::Model` and call `set_object_states`
to select states and register transaction chains for entering or leaving them.
Use `set_object_state` to request a transition. The lifetime wrapper invokes
the configured chains for the intermediate states in order and records the
result through [transaction confirmations](transactions.md#confirmations).
A transition without node work can update the record directly.

Moving back toward `active` invokes the leave handlers. Transitions back from
`hard_delete` or `deleted` are rejected. Directly changing `object_state` would
skip the operations needed to put the resource into that state.

`record_object_state_change` is a separate helper for recording a transition
whose effects the caller has already handled. It does not execute the state
change chains.

Source: [lifetime model and resource support](../api/lib/vpsadmin/api/lifetimes.rb),
[lifetime wrapper](../api/models/transaction_chains/lifetimes/wrapper.rb),
[User](../api/models/user.rb), and [VPS](../api/models/vps.rb).

## Expiration and history

An object can have an `expiration_date`. The lifetime progress task selects
expired objects and requests the next configured state. Expiration is handled
by scheduled processing, so it does not guarantee a transition at the exact
timestamp. The task also applies its configured filters and grace rules.

Default reasons and expiration intervals can be configured per object class,
state, and environment through `DefaultLifetimeValue`. Retention periods are
part of deployment policy. Use `set_expiration` when changing the date without
changing the state.

State changes record the actor, reason, state, and expiration in `ObjectState`.
API resources that include `VpsAdmin::API::Lifetimes::Resource` expose the state
parameters and a state-log child resource subject to their authorization rules.

Source: [lifetime tasks](../api/lib/vpsadmin/api/tasks/lifetimes.rb),
[default values](../api/models/default_lifetime_value.rb), and
[state history](../api/models/object_state.rb).
