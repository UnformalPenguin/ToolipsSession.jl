"""
Created in June, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
[toolips](https://github.com/orgs/ChifiSource/teams/toolips)
This software is MIT-licensed.
### ToolipsSession
**Extension for:**
- [Toolips](https://github.com/ChifiSource/Toolips.jl) \
This module provides the capability to make web-pages interactive by simply
adding the Session extension to your ServerTemplate before starting. There are
also methods contained for modifying Servables.
##### Module Composition
- [**ToolipsSession**](https://github.com/ChifiSource/ToolipsSession.jl)
"""
module ToolipsSession
using Toolips
import Toolips: ServerExtension, Servable, AbstractComponent, Modifier
import Toolips: AbstractRoute, kill!, AbstractConnection, script, write!
import Base: setindex!, getindex, push!
using Random, Dates

include("Modifier.jl")

#==
Hello, welcome to the Session source. Here is an overview of the organization
that might help you out:
------------------
- ToolipsSession.jl
--- random functions
--- Session extension
--- on
--- KeyMap
--- bind
--- script interface
--- rpc
------------------
- Modifier.jl
--- ComponentModifiers
--- Modifier functions
------------------
==#

"""
**Session**
### gen_ref() -> ::String
------------------
Creates a random string of 16 characters. This is used to map connections
to specific events by the session.
#### example
```
gen_ref()
"jfuR2wgprielweh3"
```
"""
function gen_ref(n::Int64 = 16)
    Random.seed!( rand(1:100000) )
    randstring(n)::String
end

"""
**Session Internals**
### document_linker(c::Connection) -> _
------------------
Served to /modifier/linker by the Session extension. This is where incoming
data is posted to for a response.
#### example
```

```
"""
function document_linker(c::Connection)
    s::String = getpost(c)
    ip::String = getip(c)
    reftag::UnitRange{Int64} = findfirst("??CM??", s)
    ref_r::UnitRange{Int64} = 1:minimum(reftag) -1
    ref::String = s[ref_r]
    s = replace(s, "??CM??:$ref" => "")
    if ip in keys(c[:Session].iptable)
        c[:Session].iptable[ip] = now()
    end
    if ip in keys(c[:Session].events)
        if ip * ref in keys(c[:Session].readonly)
            cm::ComponentModifier = ComponentModifier(s, c[:Session].readonly[ip * ref])
        else
            cm = ComponentModifier(s)
        end
        f::Function = c[:Session][ip][ref]
        f(cm)
        write!(c, " ")
        write!(c, cm)
    end
end

"""
**Session Interface**
### kill!(c::Connection, event::AbstractString, s::Servable) -> _
------------------
Removes a given event call from a connection's Session.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        set_text!(cm, myp, "not so wow")
    end
    write!(c, myp)
end
```
"""
function kill!(c::Connection, fname::AbstractString, s::Servable)
    refname = s.name * fname
    delete!(c[:Session][getip()], refname)
end

"""
**Session Interface**
### kill!(c::Connection)
------------------
Kills a Connection's saved events.
#### example
```
using Toolips
using ToolipsSession

route("/") do c::Connection
    on(c, "load") do cm::ComponentModifier
        alert!(cm, "this text will never appear.")
    end
    println(length(keys(c[:Session].iptable)))
    kill!(c)
    println(length(keys(c[:Session].iptable)))
end
```
"""
function kill!(c::Connection)
    delete!(c[:Session].iptable, getip(c))
    delete!(c[:Session].events, getip(c))
end

"""
### Session
- type::Vector{Symbol}
- f::Function
- active_routes::Vector{String}
- events::Dict{String, Pair{String, Function}}
- readonly::Dict{String, Vector{String}}
- iptable::Dict{String, Dates.DateTime}
- timeout::Integer\n
Provides session capabilities and full-stack interactivity to a toolips server.
Note that the route you want to be interactive **must** be in active_routes!
##### example
```
exts = [Session()]
st = ServerTemplate(extensions = exts)
server = st.start()

route!(server, "/") do c::Connection
    myp = p("myp", text = "welcome to my site")
    on(c, myp, "click") do cm::ComponentModifier
        if cm[myp][:text] == "welcome to my site"
            set_text!(cm, myp, "unwelcome to my site")
        else
            set_text!(cm, myp, "welcome to my site")
        end
    end
    write!(c, myp)
end
```
------------------
##### constructors
Session(active_routes::Vector{String} = ["/"];
        transition_duration::AbstractFloat = 0.5,
        transition::String = "ease-in-out",
        timeout::Integer = 30
        )
"""
mutable struct Session <: ServerExtension
    type::Vector{Symbol}
    f::Function
    active_routes::Vector{String}
    events::Dict{String, Dict{String, Function}}
    readonly::Dict{String, Vector{String}}
    iptable::Dict{String, Dates.DateTime}
    peers::Dict{String, Dict{String, Vector{String}}}
    timeout::Integer
    function Session(active_routes::Vector{String} = ["/"];
        transition_duration::AbstractFloat = 0.5,
        transition::AbstractString = "ease-in-out", timeout::Integer = 30,
        path::AbstractRoute = Route("/modifier/linker", x -> 5))
        events = Dict{String, Dict{String, Function}}()
        peers::Dict{String, Dict{String, Vector{String}}} = Dict{String, Dict{String, Vector{String}}}()
        iptable = Dict{String, Dates.DateTime}()
        readonly = copy(events)
        f(c::Connection, active_routes::Vector{String} = active_routes) = begin
            fullpath = c.http.message.target
            if contains(fullpath, '?')
                fullpath = split(c.http.message.target, '?')[1]
            end
            if fullpath in active_routes
                if ~(getip(c) in keys(iptable))
                    push!(events, getip(c) => Dict{String, Function}())
                    iptable[getip(c)] = now()
                else
                    if minute(now()) - minute(iptable[getip(c)]) >= timeout
                        kill!(c)
                    end
                end
                durstr = string(transition_duration, "s")
                write!(c, """<script>
                const parser = new DOMParser();
                function sendpage(ref) {
            var bodyHtml = document.getElementsByTagName('body')[0].innerHTML;
                sendinfo(ref + '??CM??' + bodyHtml);
                }
                function sendinfo(txt) {
                let xhr = new XMLHttpRequest();
                xhr.open("POST", "/modifier/linker");
                xhr.setRequestHeader("Accept", "application/json");
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.onload = () => eval(xhr.responseText);
                xhr.send(txt);
                }
                </script>
                <style type="text/css">
                #div {
                -webkit-transition: $durstr $transition;
                -moz-transition: $durstr $transition;
                -o-transition: $durstr $transition;
                transition: $durstr $transition;
                }
                </style>
                """)
            end
        end
        f(routes::Vector{AbstractRoute}, ext::Vector{ServerExtension}) = begin
            path.page = document_linker
            push!(routes, path)
        end
        new([:connection, :func, :routing], f, active_routes, events,
        readonly, iptable, peers, timeout)
    end
end


"""
**Session Interface**
### getindex(m::Session, s::AbstractString) -> ::Dict{String, Function}
------------------
Gets a session's refs by ip.
#### example
```
route("/") do c::Connection
    c[:Session][getip(c)]
end
```
"""
getindex(m::Session, s::AbstractString) = m.events[s]

"""
**Session Interface**
### getindex(m::Session, d::Dict{String, Function}, s::AbstractString) -> _
------------------
Creates a new Session.
#### example
```
route("/") do c::Connection
    c[:Session][getip(c)] = Dict{String, Function}
end
```
"""
setindex!(m::Session, d::Any, s::AbstractString) = m.events[s] = d

#==
on
==#
function on(f::Function, component::Component{<:Any}, event::String)
    cl = ClientModifier("$(component.name)$(event)")
    f(cl)
    component["on$event"] = cl.name
    push!(component.extras, script(cl))
end
# TODO more CL bindings :)
function on(f::Function, event::String)

end

"""
**Session Interface**
### on(f::Function, c::Connection, event::AbstractString, readonly::Vector{String} = Vector{String}())
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
    readonly will provide certain names to be read into the ComponentModifier.
    This can help to improve Session's performance, as it will need to parse
    less Components.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        set_text!(cm, myp, "not so wow")
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, event::AbstractString,
    readonly::Vector{String} = Vector{String}())
    ref = gen_ref()
    ip::String = getip(c)
    write!(c,
        "<script>document.addEventListener('$event', sendpage('$ref'));</script>")
    if ip in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], "$ref" => f)
    else
        c[:Session][getip(c)] = Dict("$ref" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$event$name"] = readonly
    end
end

"""
**Interface**
### on(f::Function, c::Connection, s::AbstractComponent, event::AbstractString, readonly::Vector{String} = Vector{String})
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, myp, "click")
        if cm[myp][:text] == "wow"
            c[:Logger].log("wow.")
        end
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, s::AbstractComponent,
     event::AbstractString, readonly::Vector{String} = Vector{String}())
    name::String = s.name
    ip::String = string(getip(c))
    s["on$event"] = "sendpage('$event$name');"
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][ip], "$event$name" => f)
    else
        c[:Session].events[ip] = Dict("$event$name" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$event$name"] = readonly
    end
end

"""
**Session Interface**
### on(f::Function, c::Connection, cm::ComponentModifier, event::AbstractString, readonly::Vector{String} = Vector{String}())
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
    readonly will provide certain names to be read into the ComponentModifier.
    This can help to improve Session's performance, as it will need to parse
    less Components. The ComponentModifier version can be done while in a callback.
    Remember: AbstractComponentModifiers mean callbacks, Connections mean initial requests.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        on(c, cm, "click") do cm::ComponentModifier
            set_text!(cm, myp, "not so wow")
        end
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, cm::AbstractComponentModifier, event::AbstractString,
    readonly::Vector{String} = Vector{String}())
    ip::String = getip(c)
    push!(cm.changes, """setTimeout(function () {
    document.addEventListener('$event', function () {sendpage('$event');});}, 1000);""")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], "$event" => f)
    else
        c[:Session][getip(c)] = Dict("$event" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$event"] = readonly
    end
end

"""
**Session Interface**
### on(f::Function, c::Connection, cm::ComponentModifier, event::AbstractString, readonly::Vector{String} = Vector{String}())
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
    readonly will provide certain names to be read into the ComponentModifier.
    This can help to improve Session's performance, as it will need to parse
    less Components. The ComponentModifier version can be done while in a callback.
    Remember: AbstractComponentModifiers mean callbacks, Connections mean initial requests.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        on(c, cm, "click") do cm::ComponentModifier
            set_text!(cm, myp, "not so wow")
        end
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, cm::AbstractComponentModifier, comp::Component{<:Any},
     event::AbstractString, readonly::Vector{String} = Vector{String}();
     client::Bool = false)
     name::String = comp.name
     ip::String = getip(c)
     push!(cm.changes, """setTimeout(function () {
     document.getElementById('$name').addEventListener('$event',
     function () {sendpage('$name$event');});
     }, 1000);""")
     if getip(c) in keys(c[:Session].iptable)
         push!(c[:Session][getip(c)], "$name$event" => f)
     else
         c[:Session][getip(c)] = Dict("$name$event" => f)
     end
     if length(readonly) > 0
         c[:Session].readonly["$ip$name$event"] = readonly
     end
end

#==
Input bindings
==#
"""
### abstract type InputMap
Input maps are bound using the `bind` function and allow for multiple inputs to
be registered into a `Connection` at once. Notable example from this module is `keymap`
##### Consistencies
- bound to `bind!(f::Function, ip::InputMap, args ...)`
- bound to `bind!(c::Connection, ip::InputMap)`
"""
abstract type InputMap end

"""
### KeyMap
- keys::Dict{String, Pair{Tuple, Function}}

The `KeyMap` allows one to `bind!` more than one key press with incredible ease.
##### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
------------------
##### constructors
- KeyMap()
"""
mutable struct KeyMap <: InputMap
    keys::Dict{String, Pair{Tuple, Function}}
    KeyMap() = new(Dict{String, Pair{Tuple, Function}}())
end

"""
**Session**
### bind!(f::Function, km::KeyMap, key::String, event::Symbol ...)
------------------
binds the `key` with the event keys (:ctrl, :shift, :alt) to `f` in `km`.
#### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
"""
function bind!(f::Function, km::KeyMap, key::String, event::Symbol ...)
    km.keys[key] = event => f
end

function bind!(f::Function, km::KeyMap, vs::Vector{String})
    km.keys[vs[1]] = Tuple(vs[2:length(vs)]) => f
end

"""
**Session**
### bind!(c::Connection, cm::ComponentModifier, km::KeyMap, readonly::Vector{String} = Vector{String}; on = :down)
------------------
Binds the `KeyMap` `km` to the `Connection` in a `ComponentModifier` callback.
#### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
"""
function bind!(c::Connection, km::KeyMap,
    readonly::Vector{String} = Vector{String}(); on::Symbol = :down)
    firsbind = first(km.keys)
    ip::String = getip(c)
    first_line = """setTimeout(function () {
    document.addEventListener('key$on', function(event) {"""
    for binding in km.keys
        eventstr::String = join([" event.$(event)Key && " for event in binding[2][1]])
        ref = gen_ref()
        first_line = first_line * """ if ($eventstr event.key == "$(binding[1])") {
                sendpage('$ref');
        }"""
        if ip in keys(c[:Session].iptable)
            push!(c[:Session][ip], ref => binding[2][2])
        else
            c[:Session][ip] = Dict(ref => binding[2][2])
        end
        if length(readonly) > 0
            c[:Session].readonly["$ip$key"] = readonly
        end
    end
    first_line = first_line * "});}, 1000);"
    scr = script(gen_ref(), text = first_line)
    write!(c, scr)
end

"""
**Session**
### bind!(c::Connection, cm::ComponentModifier, km::KeyMap, readonly::Vector{String} = Vector{String}; on = :down)
------------------
Binds the `KeyMap` `km` to the `Connection` in a `ComponentModifier` callback.
#### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
"""
function bind!(c::Connection, cm::ComponentModifier, km::KeyMap,
    readonly::Vector{String} = Vector{String}(); on::Symbol = :down)
    firsbind = first(km.keys)
    ip::String = getip(c)
    first_line = """setTimeout(function () {
    document.addEventListener('key$on', function(event) {"""
    for binding in km.keys
        eventstr::String = join([" event.$(event)Key && " for event in binding[2][1]])
        ref = gen_ref()
        first_line = first_line * """ if ($eventstr event.key == "$(binding[1])") {
                sendpage('$ref');
        }"""
        if ip in keys(c[:Session].iptable)
            push!(c[:Session][ip], ref => binding[2][2])
        else
            c[:Session][ip] = Dict(ref => binding[2][2])
        end
        if length(readonly) > 0
            c[:Session].readonly["$ip$key"] = readonly
        end
    end
    first_line = first_line * "});}, 1000);"
    push!(cm.changes, first_line)
end

"""
**Session**
### bind!(c::Connection, comp::Component, km::KeyMap, readonly::Vector{String} = Vector{String}; on = :down)
------------------
Binds the `KeyMap` `km` to the `comp`.
#### example
```

```
"""
function bind!(c::Connection, cm::ComponentModifier, comp::Component{<:Any},
    km::KeyMap, readonly::Vector{String} = Vector{String}(); on::Symbol = :down)
    firsbind = first(km.keys)
    ref = gen_ref()
    ip::String = getip(c)
    first_line = """
    setTimeout(function () {
    document.getElementById('$(comp.name)').addEventListener('key$on', function (event) {"""
    for binding in km.keys
        eventstr::String = join([" event.$(event)Key && " for event in binding[2][1]])
        key = binding[1]
        first_line = first_line * """ if ($eventstr event.key == "$(binding[1])") {
                sendpage('$(comp.name * binding[1] * ref)');
                }"""
        if ip in keys(c[:Session].iptable)
            push!(c[:Session][ip], comp.name * key * ref => binding[2][2])
        else
            c[:Session][ip] = Dict(comp.name * key * ref => binding[2][2])
        end
        if length(readonly) > 0
            c[:Session].readonly["$ip$key$(comp.name)"] = readonly
        end
    end
    first_line = first_line * "}.bind(event));}, 500);"
    push!(cm.changes, first_line)
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::AbstractConnection, key::String, readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------

Binds a key event to a `Component`.
#### example
```

```
"""
function bind!(f::Function, c::AbstractConnection, comp::Component{<:Any},
    key::String, eventkeys::Symbol ...; readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, client::Bool = false)
    cm::Modifier = ClientModifier()
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    if client
        f(cm)
        write!(c, """<script>
        setTimeout(function () {
    document.getElementById('$(comp.name)').addEventListener('key$on', function(event) {
        if ($eventstr event.key == "$(key)") {
        $(join(cm.changes))
        }
    });}, 1000)</script>
    """)
        return
    end
    write!(c, """<script>
    setTimeout(function () {
    document.getElementById('$(comp.name)').addEventListener('key$on', function(event) {
        if ($eventstr event.key == "$(key)") {
        sendpage('$(comp.name * key)');
        }
});}, 1000)</script>
    """)
    ip::String = getip(c)
    if ip in keys(c[:Session].iptable)
        push!(c[:Session][ip], comp.name * key => f)
    else
        c[:Session][ip] = Dict(comp.name * key => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$key"] = readonly
    end
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::AbstractConnection, key::String, readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------
Binds a key event to a `Connection`.
#### example
```

```
"""
function bind!(f::Function, c::AbstractConnection, key::String, eventkeys::Symbol ...;
    readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, client::Bool = false)
    cm::Modifier = ClientModifier()
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    ref = gen_ref()
    if client
        cm = ClientModifier()
        f(cm)
        write!(c, """<script>
        setTimeout(function () {
    document.addEventListener('key$on', function(event) {
        if ($eventstr event.key == "$(key)") {
        $(join(cm.changes))
        }
    }, 1000);</script>
    """)
        return
    end
    write!(c, """<script>
    setTimeout(function () {
document.addEventListener('key$on', function(event) {
    if ($eventstr event.key == "$(key)") {
    sendpage('$ref');
    }
});}, 1000);</script>
    """)
    ip::String = getip(c)
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][ip], ref => f)
    else
        c[:Session][ip] = Dict(ref => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$ref"] = readonly
    end
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::Connection, cm::AbstractComponentModifier, key::String, eventkeys::Symbol ...; readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------
Binds a key event to a `Connection` in a `ComponentModifier` callback.
#### example
```

```
"""
function bind!(f::Function, c::Connection, cm::AbstractComponentModifier, key::String,
    eventkeys::Symbol ...; readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, client::Bool = false)
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    ref = gen_ref()
    push!(cm.changes, """
    setTimeout(function () {
    document.addEventListener('key$on', (event) => {
            if ($eventstr event.key == "$(key)") {
            sendpage('$ref');
            }
            });}, 1000);""")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], ref => f)
    else
        c[:Session][getip(c)] = Dict(ref => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$ref"] = readonly
    end
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::Connection, cm::AbstractComponentModifier, comp::Component{<:Any}, key::String, eventkeys::Symbol ...; readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------
Binds a key event to a `Component` in a `ComponentModifier` callback.
#### example
```

```
"""
function bind!(f::Function, c::Connection, cm::AbstractComponentModifier, comp::Component{<:Any},
    key::String, eventkeys::Symbol ...; readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, client::Bool = false)
    name::String = comp.name
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    println("herherh")
push!(cm.changes, """alert("$(name)"); setTimeout(function () {
document.getElementById('$(name)').onkeydown = function(event){
        if ($eventstr event.key == '$(key)') {
        sendpage('$(name * key)')
        }
        }}, 1000);""")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], "$name$key" => f)
    else
        c[:Session][getip(c)] = Dict("$name$key" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$name$event"] = readonly
    end
end

#==
script!
==#
"""
**Session Interface** 0.3
### script!(::Function, ::Connection, ::String, readonly::Vector{String} = Vector{String}; time::Integer = 500)  -> _
------------------
Creates an "observer" which calls back to this function at each interval of `time`.
#### example
```

```
"""
function script!(f::Function, c::Connection, name::String,
    readonly::Vector{String} = Vector{String}(); time::Integer = 500,
    type::String = "Interval")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], name => f)
    else
        c[:Session][getip(c)] = Dict(name => f)
    end
    obsscript = script(name, text = """
    set$(type)(function () { sendpage('$name'); }, $time);
   """)
   if length(readonly) > 0
       c[:Session].readonly["$ip$name"] = readonly
   end
   write!(c, obsscript)
end
#==
rpc
==#

"""
**Session Interface**
### open_rpc!(c::Connection, name::String = getip(c); tickrate::Int64 = 500)
------------------
Creates a new rpc session inside of ToolipsSession. Other clients can then join and
have the same `ComponentModifier` functions run.
#### example
```

```
"""
function open_rpc!(c::Connection, name::String = getip(c); tickrate::Int64 = 500)
    push!(c[:Session].peers,
     name => Dict{String, Vector{String}}(getip(c) => Vector{String}()))
    script!(c, getip(c) * "rpc", time = tickrate) do cm::ComponentModifier
        push!(cm.changes, join(c[:Session].peers[name][getip(c)]))
        c[:Session].peers[name][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### open_rpc!(f::Function, c::Connection, name::String; tickrate::Int64 = 500)
------------------
Does the same thing as `open_rpc!(::Connection, ::String; tickrate::Int64)`,
but also runs `f` on each tick.
#### example
```

```
"""
function open_rpc!(f::Function, c::Connection, name::String; tickrate::Int64 = 500)
    push!(c[:Session].peers,
     name => Dict{String, Vector{String}}(getip(c) => Vector{String}()))
    script!(c, getip(c) * "rpc", time = tickrate) do cm::ComponentModifier
        f(cm)
        push!(cm.changes, join(c[:Session].peers[name][getip(c)]))
        c[:Session].peers[name][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### close_rpc!(c::Connection)
------------------
Removes the current RPC session from `c`.
#### example
```

```
"""
function close_rpc!(c::Connection)
    delete!(c[:Session].peers, getip(c))
end

"""
**Session Interface**
### join_rpc!(c::Connection, host::String; tickrate::Int64 = 500)
------------------
Joins an rpc session by name.
#### example
```

```
"""
function join_rpc!(c::Connection, host::String; tickrate::Int64 = 500)
    push!(c[:Session].peers[host], getip(c) => Vector{String}())
    script!(c, getip(c) * "rpc", time = tickrate) do cm::ComponentModifier
        location::String = find_client(c)
        push!(cm.changes, join(c[:Session].peers[location][getip(c)]))
        c[:Session].peers[location][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### join_rpc!(f::Function, c::Connection, host::String; tickrate::Int64 = 500)
------------------
Joins an rpc session by name, runs `f` on each tick.
#### example
```

```
"""
function join_rpc!(f::Function, c::Connection, host::String; tickrate::Int64 = 500)
    push!(c[:Session].peers[host], getip(c) => Vector{String}())
    script!(c, getip(c) * "rpc", time = tickrate) do cm::ComponentModifier
        f(cm)
        location::String = find_client(c)
        push!(cm.changes, join(c[:Session].peers[location][getip(c)]))
        c[:Session].peers[location][getip(c)] = Vector{String}()
    end
    f(cm)
end

"""
**Session Interface**
### find_client(c::Connection)
------------------
Finds the RPC session name of this client.
#### example
```

```
"""
function find_client(c::Connection)
    clientlocation = findfirst(x -> getip(c) in keys(x), c[:Session].peers)
    clientlocation::String
end

"""
**Session Interface**
### rpc!(c::Connection, cm::ComponentModifier)
------------------
Does an rpc for all other connection clients, also clears `ComponentModifier` changes.
 You can use this interchangeably with local function calls by calling `rpc!` first
then calling your regular `ComponentModifier` functions.
#### example
```

```
"""
function rpc!(c::Connection, cm::ComponentModifier)
    mods::String = find_client(c)
    [push!(mod, join(cm.changes)) for mod in values(c[:Session].peers[mods])]
    deleteat!(cm.changes, 1:length(cm.changes))
end

"""
**Session Interface**
### rpc!(f::Function, c::Connection)
------------------
Does RPC with a new `ComponentModifier` and will rpc everything inside of `f`.
#### example
```
rpc!(c) do cm::ComponentModifier

end
```
"""
function rpc!(f::Function, c::Connection)
    cm = ComponentModifier("")
    f(cm)
    mods::String = find_client(c)
    for mod in values(c[:Session].peers[mods])
        push!(mod.changes, join(cm.changes))
    end
end

"""
**Session Interface**
### disconnect_rpc!(c::Connection)
------------------
Removes the client from the current rpc session.
#### example
```

```
"""
function disconnect_rpc!(c::Connection)
    mods::String = find_client(c)
    delete!(c[:Session].peers[mods], getip(c))
end

"""
**Session Interface**
### is_host(c::Connection) -> ::Bool
------------------
Checks if the current `Connection` is hosting an rpc session.
#### example
```

```
"""
is_host(c::Connection) = getip(c) in keys(c[:Session].peers)

"""
**Session Interface**
### is_client(c::Connection, s::String) -> ::Bool
------------------
Checks if the client is in the `s` RPC session..
#### example
```

```
"""
is_client(c::Connection, s::String) = getip(c) in keys(c[:Session].peers[s])

"""
**Session Interface**
### is_dead(c::Connection) -> ::Bool
------------------
Checks if the current `Connection` is still connected to `Session`
#### example
```

```
"""
is_dead(c::Connection) = getip(c) in keys(c[:Session].iptable)

export Session, on, bind!, script!, script, ComponentModifier, ClientModifier
export KeyMap
export playanim!, alert!, redirect!, modify!, move!, remove!, set_text!
export update!, insert_child!, append_first!, animate!, pauseanim!, next!
export set_children!, get_text, style!, free_redirects!, confirm_redirects!
export scroll_by!, scroll_to!, focus!, set_selection!
export rpc!, disconnect_rpc!, find_client, join_rpc!, close_rpc!, open_rpc!
export join_rpc!, is_client, is_dead, is_host
end # module
