module Retries exposing (Tried, entryUpdater)

import Updaters exposing (Updater)


type alias Tried cmsg nick =
    { msg : cmsg
    , nick : nick
    }


type alias Interface base cmodel model cmsg msg =
    { base
        | localUpdate : Updater cmodel cmsg -> Updater model msg
        , lowerModel : model -> cmodel
    }


type alias RetriableModel cmodel cmsg nick =
    { cmodel
        | retry : Maybe (Tried cmsg nick)
    }


entryUpdater :
    Interface base (RetriableModel cmodel cmsg nick) model cmsg msg
    -> Updater (RetriableModel cmodel cmsg nick) cmsg
    -> Updater (RetriableModel cmodel cmsg nick) cmsg
    -> (Interface base (RetriableModel cmodel cmsg nick) model cmsg msg -> cmsg -> Updater model msg)
    -> nick
    -> Updater model msg
entryUpdater ({ lowerModel, localUpdate } as iface) fetchUpdater retryUpdater updaters nick model =
    let
        doFetch =
            localUpdate fetchUpdater
    in
    case (lowerModel model).retry of
        Just tried ->
            if nick == tried.nick then
                Updaters.compose
                    (localUpdate retryUpdater)
                    (updaters iface tried.msg)
                    model

            else
                doFetch model

        Nothing ->
            doFetch model
