
This library supports the use of Updaters, which are useful if you are flaunting received Elm
wisdom and composing TEA-style modules. That kind of composition starts to want to transmit
changes up the tree of composition, which can be complicated. (Maybe this is why it's discouraged;
everything is tradeoffs though, and if the author hadn't felt that encapsulating behavior wasn't valuable,
this package wouldn't exist.)

The approach used here is something like the Protocol pattern (and can be used as opposed to,
e.g. the OutMsg Pattern.) You'll do something like:

```elm
    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
          -- assume handling of various messages here

          ChildMsg submsg ->
            Child.updater interface submsg model
```

Mostly straightforward TEA Main.elm. Instead of having its own `update` function,
our child component (there, I said it) has an `updater` function, which is similar
to `update` but receives an extra `interface` argument, like this:

```elm
    updater : Interface base model msg -> Msg -> Updater model msg
    updater ({ installNewCred, requestNav } as iface) msg =
      -- ...
```

because of the definition of `Updater`, the type signature of `updater` is equivalent to

```elm
    updater : Interface base model msg
        -> Msg -> Model -> (Model, Cmd Msg)
```

In other words, `updater interface` is the same as a TEA `update`.

At the root of our application, the interface looks like:

```elm
    interface :
        { requestNav : Router.Target -> Model -> ( Model, Cmd Msg )
        , sendToast : Pages.Toast -> Model -> ( Model, Cmd Msg )
        , installNewCred : Auth.Cred -> Model -> ( Model, Cmd Msg )
        , localUpdate : Updater Pages.Models Pages.Msg -> Model -> ( Model, Cmd Msg )
        , handleError : Error -> Updater Model Msg
        }
    interface =
        { requestNav = onNav
        , sendToast = PageToast >> onAddToast
        , installNewCred = onNewCred
        , localUpdate = childUpdate
        , handleError = handleError
        }
```

If you've used (or considered) an `OutMsg` style composition pattern,
you might see the parallel between
the interface struct and an OutMsg type.
One nice feature of the interface is that the _receiver_ defines its shape,
rather than needing a extra shared module
that defines the messages far from their use.
Additionally, Updaters can be _composed_, (akin to Cmd.batch)
which can require fiddly extra handling for OutMsgs.
