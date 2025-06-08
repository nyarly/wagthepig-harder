module Updaters exposing
    ( UpdateList
    , Updater
    , childUpdate
    , comp
    , compose
    , noChange
    )


type alias Updater model msg =
    model -> ( model, Cmd msg )


type alias UpdateList model msg =
    List (Updater model msg)


noChange : Updater model msg
noChange model =
    ( model, Cmd.none )


childUpdate : (pmodel -> cmodel) -> (pmodel -> cmodel -> pmodel) -> (cmsg -> pmsg) -> Updater cmodel cmsg -> Updater pmodel pmsg
childUpdate getModel setModel wrapMsg upper model =
    getModel model
        |> upper
        |> Tuple.mapBoth (setModel model) (Cmd.map wrapMsg)


compose : UpdateList model msg -> Updater model msg
compose updaters model =
    let
        acc =
            ( model, [] )

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


comp : Updater model msg -> Updater model msg -> Updater model msg
comp left right mod =
    let
        ( lmod, lcmd ) =
            left mod

        ( rmod, rcmd ) =
            right lmod
    in
    ( rmod, Cmd.batch [ lcmd, rcmd ] )
