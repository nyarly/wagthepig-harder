module OutMsg exposing (Msg(..), MainMsg(..), PageMsg(..), mapBoth, addNone)

import Router
import Auth
import Hypermedia as HM

type Msg
  = None
  | Main MainMsg
  | Page PageMsg

type MainMsg
  = Nav Router.Target
  | NewCred Auth.Cred

type PageMsg
  = CreateEvent HM.Affordance
  | EditEvent Auth.Cred HM.Affordance

mapBoth : (chModel -> pModel) -> (chMsg -> pMsg) -> ( chModel, chMsg, Msg ) -> ( pModel, pMsg, Msg )
mapBoth mapMod mapMsg (model, msg, outmsg) =
  (mapMod model, mapMsg msg, outmsg)

addNone : (model, msg) -> (model, msg, Msg)
addNone (model, msg) =
  (model, msg, None)
