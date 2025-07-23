module Updaters exposing
    ( Updater
    , compose, composeList
    , childUpdate, noChange
    , Tried, entryUpdater
    )

{-| Machenary and tooling around interface-pattern TEA composition


# Updaters

@docs Updater


# Manipulating Updaters

@docs compose, composeList


# Tools for making Updaters

@docs childUpdate, noChange


# Utilities

@docs Tried, entryUpdater

-}


{-| A type alias for a function that takes a model and returns a TEA update tuple.
We can use this in a child component, returning an Updater based on what message was passed.
The root component can then apply the Updater to its model, and return the (model, cmd)
tuple that Elm expects from its update function.
-}
type alias Updater model msg =
    model -> ( model, Cmd msg )


{-| Tried encapsulates an operation that might fail and that we might want to try again.
The `msg` field is used to record the message that triggered the operation,
and `nick` is used to descriminate states, so that we don't retry a stale operation.
-}
type alias Tried cmsg nick =
    { msg : cmsg
    , nick : nick
    }


type alias RetriableModel cmodel cmsg nick =
    { cmodel
        | retry : Maybe (Tried cmsg nick)
    }


{-| The no-op Updater. Used when a component has to receive a message
(e.g. to simplify its use alongside other components)
but it doesn't do anything.

Also handy when you don't have an implementation for a message yet.

-}
noChange : Updater model msg
noChange model =
    ( model, Cmd.none )


{-| This function lets us do updates in a child component, but with the parent's model and messages.
In general you'd use it like:

    childUpdate : Updater Pages.Models Pages.Msg -> Updater Model Msg
    childUpdate =
        Updaters.childUpdate .pages (\model -> \pagemodel -> { model | pages = pagemodel }) PageMsg

In the above case, we use `.pages` to extract a field from the parent model,
the lambda updates the `pages` field in the parent model with the child model,
and `PageMsg` wraps whatever message the child emits.

-}
childUpdate : (pmodel -> cmodel) -> (pmodel -> cmodel -> pmodel) -> (cmsg -> pmsg) -> Updater cmodel cmsg -> Updater pmodel pmsg
childUpdate getModel setModel wrapMsg upper model =
    getModel model
        |> upper
        |> Tuple.mapBoth (setModel model) (Cmd.map wrapMsg)


{-| It's not uncommon to have a List(Updater) that you want to compose into a single Updater,
which is what this function is for. Generally, prefer pairwise use of `compose`

    composeList [ updateName name, requestNewForms name ]

-}
composeList : List (Updater model msg) -> Updater model msg
composeList updaters model =
    let
        acc : ( model, List cmd )
        acc =
            ( model, [] )

        reduce : Updater model msg -> ( model, List (Cmd msg) ) -> ( model, List (Cmd msg) )
        reduce updater ( mod, clist ) =
            let
                ( newmod, cmd ) =
                    updater mod
            in
            ( newmod, cmd :: clist )

        ( finalmodel, cmdlist ) =
            List.foldl reduce acc updaters
    in
    ( finalmodel, Cmd.batch cmdlist )


{-| Put two Updaters together into one!
Specifically, they're run in sequence
(so the second Updater sees the result model from the second),
and their `Cmd`s are `batch`ed up.

    compose
        (doSomething Fancy)
        (makeHttpRequest reqDescription)
        >> compose anotherThing

-}
compose : Updater model msg -> Updater model msg -> Updater model msg
compose left right mod =
    let
        ( lmod, lcmd ) =
            left mod

        ( rmod, rcmd ) =
            right lmod
    in
    ( rmod, Cmd.batch [ lcmd, rcmd ] )


type alias Interface base cmodel model cmsg msg =
    { base
        | localUpdate : Updater cmodel cmsg -> Updater model msg
        , lowerModel : model -> cmodel
    }


{-| This can be used in a component to set up it's load-based retrier
Specifically we check if there is a `Just Tried` stored as `retry` on the local model, and that the Tried matches our nick.
If so, we re-do the retried command.
Otherwise, we just run the first updater, which is the thing that might fail,
and use the second updater that stashes the retry.
-}
entryUpdater :
    Interface base (RetriableModel cmodel cmsg nick) model cmsg msg
    -> Updater (RetriableModel cmodel cmsg nick) cmsg
    -> Updater (RetriableModel cmodel cmsg nick) cmsg
    -> (Interface base (RetriableModel cmodel cmsg nick) model cmsg msg -> cmsg -> Updater model msg)
    -> nick
    -> Updater model msg
entryUpdater ({ lowerModel, localUpdate } as iface) fetchUpdater retryUpdater updater nick model =
    let
        doFetch : model -> ( model, Cmd msg )
        doFetch =
            localUpdate fetchUpdater
    in
    case (lowerModel model).retry of
        Just tried ->
            if nick == tried.nick then
                compose
                    (localUpdate retryUpdater)
                    (updater iface tried.msg)
                    model

            else
                doFetch model

        Nothing ->
            doFetch model
