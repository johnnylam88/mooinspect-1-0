Overview
--------

[MooInspect-1.0][project] is a library that provides an API for asynchronous inspection of unit specialization, talents, and equipment.

The native API for asynchronous inspection uses [NotifyInspect] for an inspection request and waiting for the [INSPECT_READY] event to indicate the inspection data is available.  However the server will drop all inspection requests originating from the account if too many requests are initiated in too short a period of time.

__MooInspect-1.0__ limits the frequency of calls to [NotifyInspect] and keeps a queue of pending inspection requests to send to the server while out of combat.  When the inspection data from a request becomes available, the message [MooInspect_InspectReady](#inspectready) is fired.


API Methods
-----------

### QueueInspect

Queues an inspection request for a GUID.

    lib:QueueInspect(guid)

#### Arguments:

* `guid` - string: [GUID][]

### CancelInspect

Cancels any pending inspection request for a GUID.

    lib:CancelInspect(guid)

#### Arguments:

* `guid` - string: [GUID][]

### GetInspectAge

Returns the number of seconds since the inspection data for a GUID was received from the server.  If no inspection data has ever been received, then this returns `nil`.

    age = lib:GetInspectAge(guid)

#### Arguments:

* `guid` - string: [GUID][]

#### Returns:

* `age` - number or `nil`: seconds since the data was received

### RegisterCallback

Registers a function to handle the specified callback.

    lib.RegisterCallback(handler, callback, method, arg)

#### Arguments:

* `handler` - table/string: your addon object or another table containing a function at `handler[method]`, or a string identifying your addon
* `callback` - string: the name of the callback to be registered
* `method` - string/function/nil: a key into the `handler` table, or a function to be called, or `nil` if `handler` is a table and a function exists at `handler[callback]`
* `arg` - a value to be passed as the first argument to the callback function specified by `method`

#### Notes:

* If `handler` is a table, `method` is a string, and `handler[method]` is a function, then that function will be called with `handler` as its first argument, followed by the callback name and the callback-specific arguments.
* If `handler` is a table, `method` is nil, and `handler[callback]` is a function, then that function will be called with `handler` as its first argument, followed by the callback name and the callback-specific arguments.
* If `handler` is a string and `method` is a function, then that function will be called with the callback name as its first argument, followed by the callback-specific arguments.
* If `arg` is non-nil, then it will be passed to the specified function. If `handler` is a table, then `arg` will be passed as the second argument, pushing the callback name to the third position. Otherwise, `arg` will be passed as the first argument.

### UnregisterCallback

Unregisters a specified callback.

    lib.UnregisterCallback(handler, callback)

#### Arguments:

* `handler` - table/string: your addon object or a string identifying your addon
* `callback` - string: the name of the callback to be unregistered


Callbacks
---------

__MooInspect-1.0__ provides the following callbacks to notify interested addons.

### [MooInspect_InspectReady](#inspectready)

Fires when the inspection data for a GUID is available for talent and equipment queries.

#### Arguments:

* `guid` - string: [GUID][]


License
-------
__MooInspect-1.0__ is released under the 2-clause BSD license.


Feedback
--------

+ [Report a bug or suggest a feature][project-issue-tracker].

  [project]: https://www.github.com/ultijlam/mooinspect-1-0
  [project-issue-tracker]: https://github.com/ultijlam/mooinspect-1-0/issues

  [INSPECT_READY]: https://wow.gamepedia.com/INSPECT_READY
  [GUID]: https://wow.gamepedia.org/GUID
  [NotifyInspect]: https://wow.gamepedia.com/API_NotifyInspect