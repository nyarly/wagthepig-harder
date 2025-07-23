module Pages exposing (Interface, Models, Msg(..), Toast, afterLoginUpdater, init, pageNavMsg, updaters, view, viewToast)

import Auth
import CompleteRegistration
import EventEdit
import EventShow
import Events
import Game.Create
import Game.Edit
import Game.View
import Html exposing (Html)
import Hypermedia exposing (Affordance, Error)
import Landing
import Login
import Profile
import Register
import Router exposing (Target(..))
import Toast
import Updaters exposing (Updater, childUpdate, noChange)
import WhatShouldWePlay


type Msg
    = LandingMsg Landing.Msg
    | LoginMsg Login.Msg
    | ProfileMsg Profile.Msg
    | EventsMsg Events.Msg
    | EventEditMsg EventEdit.Msg
    | GameCreateMsg Game.Create.Msg
    | GameEditMsg Game.Edit.Msg
    | EventShowMsg EventShow.Msg
    | WhatShouldWePlayMsg WhatShouldWePlay.Msg
    | RegisterMsg Register.Msg
    | CompleteRegistrationMsg CompleteRegistration.Msg
    | CredentialedArrivalMsg Auth.Cred Target



{-
   future iterations: use the named record pattern thing
   e.g. (in a page)
   type alias Model = { model | fields: String, needed: Bool, here: Nick }
   then there's one app model in Main, and modules to manage special types
   (in this case Game, Event)

   pro: Pages just passes the model on, we don't repeat things like creds
-}


type alias Models =
    { landing : Landing.Model
    , login : Login.Model
    , profile : Profile.Model
    , events : Events.Model
    , reccos : WhatShouldWePlay.Model
    , event : EventEdit.Model
    , games : EventShow.Model
    , editGame : Game.Edit.Model
    , createGame : Game.Create.Model
    , register : Register.Model
    , complete_registration : CompleteRegistration.Model
    }


type Toast
    = EventEditToast EventEdit.Toast
    | EventShowToast EventShow.Toast
    | LoginToast Login.Toast
    | GameCreateToast Game.View.Toast
    | GameEditToast Game.View.Toast
    | ProfileToast Profile.Toast
    | WhatShouldWePlayToast WhatShouldWePlay.Toast


init : Models
init =
    Models
        Landing.Model
        Login.init
        Profile.init
        Events.init
        WhatShouldWePlay.init
        EventEdit.init
        EventShow.init
        Game.Edit.init
        Game.Create.init
        Register.init
        CompleteRegistration.init


view : Router.Target -> Models -> List (Html Msg)
view target models =
    let
        wrapMsg : (a -> msg) -> List (Html a) -> List (Html msg)
        wrapMsg msg htmls =
            List.map (Html.map msg) htmls
    in
    case target of
        Router.CredentialedArrival _ _ ->
            []

        Router.Landing ->
            Landing.view models.landing
                |> wrapMsg LandingMsg

        Router.Login ->
            Login.view models.login
                |> wrapMsg LoginMsg

        Router.Profile ->
            Profile.view models.profile
                |> wrapMsg ProfileMsg

        Router.Events sort ->
            Events.view models.events sort
                |> wrapMsg EventsMsg

        Router.EventEdit _ ->
            EventEdit.view models.event
                |> wrapMsg EventEditMsg

        Router.EventShow _ sorting ->
            EventShow.view models.games sorting
                |> wrapMsg EventShowMsg

        Router.WhatShouldWePlay _ sorting ->
            WhatShouldWePlay.view models.reccos sorting
                |> wrapMsg WhatShouldWePlayMsg

        Router.CreateEvent ->
            EventEdit.view models.event
                |> wrapMsg EventEditMsg

        Router.CreateGame _ ->
            Game.Create.view models.createGame
                |> wrapMsg GameCreateMsg

        Router.EditGame _ _ ->
            Game.Edit.view models.editGame
                |> wrapMsg GameEditMsg

        Router.Register ->
            Register.view models.register
                |> wrapMsg RegisterMsg

        Router.CompleteRegistration _ ->
            CompleteRegistration.view models.complete_registration
                |> wrapMsg CompleteRegistrationMsg


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    let
        unwrapToast info content =
            Toast.Info info.id info.phase info.interaction content

        wrapHtml : (a -> msg) -> List (Html a) -> List (Html msg)
        wrapHtml pageMsg =
            List.map (Html.map pageMsg)
    in
    case toastInfo.content of
        EventEditToast subToast ->
            EventEdit.viewToast (unwrapToast toastInfo subToast) |> wrapHtml EventEditMsg

        EventShowToast subToast ->
            EventShow.viewToast (unwrapToast toastInfo subToast) |> wrapHtml EventShowMsg

        LoginToast subToast ->
            Login.viewToast (unwrapToast toastInfo subToast) |> wrapHtml LoginMsg

        GameCreateToast subToast ->
            Game.Create.viewToast (unwrapToast toastInfo subToast) |> wrapHtml GameCreateMsg

        GameEditToast subToast ->
            Game.Edit.viewToast (unwrapToast toastInfo subToast) |> wrapHtml GameEditMsg

        ProfileToast subToast ->
            Profile.viewToast (unwrapToast toastInfo subToast) |> wrapHtml ProfileMsg

        WhatShouldWePlayToast subToast ->
            WhatShouldWePlay.viewToast (unwrapToast toastInfo subToast) |> wrapHtml WhatShouldWePlayMsg


pageNavMsg : Router.Target -> Auth.Cred -> Msg
pageNavMsg target creds =
    case target of
        Router.CredentialedArrival next cred ->
            CredentialedArrivalMsg cred next

        Router.Profile ->
            ProfileMsg (Profile.Entered creds Profile.Creds)

        Router.Events sort ->
            EventsMsg (Events.Entered creds sort)

        Router.Register ->
            RegisterMsg Register.Entered

        Router.EventShow id _ ->
            EventShowMsg (EventShow.Entered creds (EventShow.Nickname id))

        Router.WhatShouldWePlay id _ ->
            WhatShouldWePlayMsg (WhatShouldWePlay.Entered creds (WhatShouldWePlay.Nick id))

        Router.CreateEvent ->
            EventEditMsg (EventEdit.Entered creds EventEdit.None)

        Router.EventEdit id ->
            EventEditMsg (EventEdit.Entered creds (EventEdit.Nickname id))

        Router.CreateGame ev ->
            GameCreateMsg (Game.Create.Entered creds ev)

        Router.EditGame event_id game_id ->
            GameEditMsg (Game.Edit.Entered creds event_id game_id)

        Router.CompleteRegistration email ->
            CompleteRegistrationMsg (CompleteRegistration.Entered creds email)

        Login ->
            LoginMsg Login.Entered

        Landing ->
            LandingMsg Landing.Entered


type alias Interface base model msg =
    { base
        | localUpdate : Updater Models Msg -> Updater model msg
        , relogin : Updater model msg
        , requestNav : Router.Target -> Updater model msg
        , requestUpdatePath : Router.Target -> Updater model msg
        , installNewCred : Auth.Cred -> Updater model msg
        , lowerModel : model -> Models
        , sendToast : Toast -> Updater model msg
        , handleError : Error -> Updater model msg
        , handleErrorWithRetry : Updater model msg -> Error -> Updater model msg
    }


createEventUpdater : Interface base model msg -> Affordance -> Updater model msg
createEventUpdater { localUpdate, requestNav } aff =
    Updaters.composeList
        [ localUpdate (\models -> ( { models | event = EventEdit.forCreate aff }, Cmd.none ))
        , requestNav Router.CreateEvent
        ]


childInterface :
    Interface base model msg
    -> (ctoast -> Toast)
    -> (Models -> cmodel)
    -> (Models -> cmodel -> Models)
    -> (cmsg -> Msg)
    ->
        { requestNav : Router.Target -> Updater model msg
        , relogin : Updater model msg
        , requestUpdatePath : Router.Target -> Updater model msg
        , installNewCred : Auth.Cred -> Updater model msg
        , requestCreateEvent : Affordance -> Updater model msg
        , lowerModel : model -> cmodel
        , localUpdate : Updater cmodel cmsg -> Updater model msg
        , sendToast : ctoast -> Updater model msg
        , handleError : Error -> Updater model msg
        , handleErrorWithRetry : Updater model msg -> Error -> Updater model msg
        }
childInterface iface wrapToast getModel setModel wrapMsg =
    let
        { requestNav, requestUpdatePath, installNewCred, localUpdate, lowerModel, sendToast, relogin, handleError, handleErrorWithRetry } =
            iface
    in
    { requestNav = requestNav
    , relogin = relogin
    , handleError = handleError
    , handleErrorWithRetry = handleErrorWithRetry
    , requestUpdatePath = requestUpdatePath
    , installNewCred = installNewCred
    , requestCreateEvent = createEventUpdater iface
    , lowerModel = lowerModel >> getModel
    , localUpdate = localUpdate << childUpdate getModel setModel wrapMsg
    , sendToast = wrapToast >> sendToast
    }


afterLoginUpdater :
    Interface base model msg
    -> Router.Target
    -> Updater model msg
afterLoginUpdater iface target =
    let
        ciface =
            childInterface iface LoginToast .login (\models -> \pm -> { models | login = pm }) LoginMsg
    in
    Login.nextPageUpdater ciface target


updaters : Interface base model msg -> Msg -> Updater model msg
updaters ({ installNewCred, requestNav } as iface) msg =
    let
        pageInterface =
            childInterface iface
    in
    case msg of
        CredentialedArrivalMsg cred next ->
            Updaters.compose (installNewCred cred)
                (requestNav next)

        LandingMsg _ ->
            noChange

        ProfileMsg submsg ->
            Profile.updaters
                (pageInterface ProfileToast .profile (\models -> \pm -> { models | profile = pm }) ProfileMsg)
                submsg

        LoginMsg submsg ->
            Login.updaters
                (pageInterface LoginToast .login (\models -> \pm -> { models | login = pm }) LoginMsg)
                submsg

        EventsMsg submsg ->
            Events.updaters
                (pageInterface identity .events (\models -> \pm -> { models | events = pm }) EventsMsg)
                submsg

        EventEditMsg submsg ->
            EventEdit.updaters
                (pageInterface EventEditToast .event (\models -> \pm -> { models | event = pm }) EventEditMsg)
                submsg

        EventShowMsg submsg ->
            EventShow.updaters
                (pageInterface EventShowToast .games (\models -> \pm -> { models | games = pm }) EventShowMsg)
                submsg

        WhatShouldWePlayMsg submsg ->
            WhatShouldWePlay.updaters
                (pageInterface WhatShouldWePlayToast .reccos (\models -> \pm -> { models | reccos = pm }) WhatShouldWePlayMsg)
                submsg

        RegisterMsg submsg ->
            Register.updaters
                (pageInterface identity .register (\models -> \pm -> { models | register = pm }) RegisterMsg)
                submsg

        CompleteRegistrationMsg submsg ->
            CompleteRegistration.updaters
                (pageInterface identity .complete_registration (\models -> \pm -> { models | complete_registration = pm }) CompleteRegistrationMsg)
                submsg

        GameEditMsg submsg ->
            Game.Edit.updaters
                (pageInterface GameEditToast .editGame (\models -> \pm -> { models | editGame = pm }) GameEditMsg)
                submsg

        GameCreateMsg submsg ->
            Game.Create.updaters
                (pageInterface GameCreateToast .createGame (\models -> \pm -> { models | createGame = pm }) GameCreateMsg)
                submsg
