module OutMsg exposing (MainMsg(..), Msg(..), PageMsg(..), addNone, mapBoth)

import Auth
import Hypermedia as HM
import Router



{-
   We extend TEA with an alternative to
   update : Msg -> Model -> ( Model, Cmd Msg )

   like this:
   bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )

   a component (there, I said it) that uses bidiupdate (that is: bi-directional update)
   can emit an OutMsg.Msg to be sent up the tree.
-}
-- All these messages have to be here at the "bottom" of the import heirarchy
-- In a way, they serve as the map of how to send messages up the inclusion tree.


type Msg
    = None
    | Main MainMsg
    | Page PageMsg


type MainMsg
    = Nav Router.Target
    | NewCred Auth.Cred Router.Target


type
    PageMsg
    -- time being, I'm leaving this as a cautionary tale:
    -- "change page" -> a link. a [ href Router.buildFromTarget ... ]
    = CreateEvent HM.Affordance


mapBoth : (chModel -> pModel) -> (chMsg -> pMsg) -> ( chModel, chMsg, Msg ) -> ( pModel, pMsg, Msg )
mapBoth mapMod mapMsg ( model, msg, outmsg ) =
    ( mapMod model, mapMsg msg, outmsg )


addNone : ( model, msg ) -> ( model, msg, Msg )
addNone ( model, msg ) =
    ( model, msg, None )
