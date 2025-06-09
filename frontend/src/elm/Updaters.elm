module Updaters exposing
    ( Updater
    , childUpdate
    , compose
    , composeList
    , noChange
    )


type alias Updater model msg =
    model -> ( model, Cmd msg )


noChange : Updater model msg
noChange model =
    ( model, Cmd.none )


childUpdate : (pmodel -> cmodel) -> (pmodel -> cmodel -> pmodel) -> (cmsg -> pmsg) -> Updater cmodel cmsg -> Updater pmodel pmsg
childUpdate getModel setModel wrapMsg upper model =
    getModel model
        |> upper
        |> Tuple.mapBoth (setModel model) (Cmd.map wrapMsg)


composeList : List (Updater model msg) -> Updater model msg
composeList updaters model =
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


compose : Updater model msg -> Updater model msg -> Updater model msg
compose left right mod =
    let
        ( lmod, lcmd ) =
            left mod

        ( rmod, rcmd ) =
            right lmod
    in
    ( rmod, Cmd.batch [ lcmd, rcmd ] )
