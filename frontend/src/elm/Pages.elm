module Pages exposing (Models, Msg(..), bidiupdate, init, pageNav, view)

import Auth
import CompleteRegistration
import EventEdit
import EventShow
import Events
import Html exposing (Html)
import Landing
import Login
import OutMsg
import Profile
import Register
import Router exposing (Target(..))


type Msg
    = LandingMsg Landing.Msg
    | LoginMsg Login.Msg
    | ProfileMsg Profile.Msg
    | EventsMsg Events.Msg
    | EventEditMsg EventEdit.Msg
    | EventShowMsg EventShow.Msg
    | RegisterMsg Register.Msg
    | CompleteRegistrationMsg CompleteRegistration.Msg


type alias Models =
    { landing : Landing.Model
    , login : Login.Model
    , profile : Profile.Model
    , events : Events.Model
    , event : EventEdit.Model
    , games : EventShow.Model
    , register : Register.Model
    , complete_registration : CompleteRegistration.Model
    }


init : Models
init =
    Models
        Landing.Model
        Login.init
        Profile.init
        Events.init
        EventEdit.init
        EventShow.init
        Register.init
        CompleteRegistration.init


view : Router.Target -> Models -> (Msg -> msg) -> List (Html msg)
view target models toMsg =
    let
        wrapMsg msg htmls =
            List.map (Html.map (\m -> toMsg (msg m))) htmls
    in
    case target of
        Router.CredentialedArrival _ _ ->
            []

        --XXX
        Router.Landing ->
            Landing.view models.landing
                |> wrapMsg LandingMsg

        Router.Login ->
            Login.view models.login
                |> wrapMsg LoginMsg

        Router.Profile ->
            Profile.view models.profile
                |> wrapMsg ProfileMsg

        Router.Events ->
            Events.view models.events
                |> wrapMsg EventsMsg

        Router.EventEdit _ ->
            EventEdit.view models.event
                |> wrapMsg EventEditMsg

        Router.EventShow _ ->
            EventShow.view models.games
                |> wrapMsg EventShowMsg

        Router.CreateEvent ->
            EventEdit.view models.event
                |> wrapMsg EventEditMsg

        Router.Register ->
            Register.view models.register
                |> wrapMsg RegisterMsg

        Router.CompleteRegistration _ ->
            CompleteRegistration.view models.complete_registration
                |> wrapMsg CompleteRegistrationMsg


pageNav : Router.Target -> Auth.Cred -> Models -> ( Models, Cmd Msg, OutMsg.Msg )
pageNav target creds models =
    case target of
        Router.CredentialedArrival next cred ->
            ( models, Cmd.none, OutMsg.Main (OutMsg.NewCred cred next) )

        Router.Profile ->
            bidiupdate (ProfileMsg (Profile.Entered creds Profile.Creds)) models

        Router.Events ->
            bidiupdate (EventsMsg (Events.Entered creds)) models

        Router.Register ->
            bidiupdate (RegisterMsg Register.Entered) models

        Router.CreateEvent ->
            bidiupdate (EventEditMsg (EventEdit.Entered creds EventEdit.None)) models

        Router.EventEdit id ->
            bidiupdate (EventEditMsg (EventEdit.Entered creds (EventEdit.Nickname id))) models

        Router.CompleteRegistration email ->
            bidiupdate (CompleteRegistrationMsg (CompleteRegistration.Entered creds email)) models

        _ ->
            ( models, Cmd.none, OutMsg.None )


bidiupdate : Msg -> Models -> ( Models, Cmd Msg, OutMsg.Msg )
bidiupdate msg models =
    case msg of
        LandingMsg _ ->
            ( models, Cmd.none, OutMsg.None )

        ProfileMsg submsg ->
            Profile.bidiupdate submsg models.profile
                |> OutMsg.mapBoth (\pm -> { models | profile = pm }) (Cmd.map ProfileMsg)
                |> consumeOutmsg

        LoginMsg submsg ->
            Login.bidiupdate submsg models.login
                |> OutMsg.mapBoth (\pm -> { models | login = pm }) (Cmd.map LoginMsg)
                |> consumeOutmsg

        EventsMsg submsg ->
            Events.bidiupdate submsg models.events
                |> OutMsg.mapBoth (\pm -> { models | events = pm }) (Cmd.map EventsMsg)
                |> consumeOutmsg

        EventEditMsg submsg ->
            EventEdit.bidiupdate submsg models.event
                |> OutMsg.mapBoth (\pm -> { models | event = pm }) (Cmd.map EventEditMsg)
                |> consumeOutmsg

        EventShowMsg submsg ->
            EventShow.bidiupdate submsg models.games
                |> OutMsg.mapBoth (\pm -> { models | games = pm }) (Cmd.map EventShowMsg)
                |> consumeOutmsg

        RegisterMsg submsg ->
            Register.bidiupdate submsg models.register
                |> OutMsg.mapBoth (\pm -> { models | register = pm }) (Cmd.map RegisterMsg)
                |> consumeOutmsg

        CompleteRegistrationMsg submsg ->
            CompleteRegistration.bidiupdate submsg models.complete_registration
                |> OutMsg.mapBoth (\pm -> { models | complete_registration = pm }) (Cmd.map CompleteRegistrationMsg)
                |> consumeOutmsg


consumeOutmsg : ( Models, Cmd Msg, OutMsg.Msg ) -> ( Models, Cmd Msg, OutMsg.Msg )
consumeOutmsg ( models, cmd, out ) =
    case out of
        OutMsg.Page pagemsg ->
            case pagemsg of
                OutMsg.CreateEvent aff ->
                    ( { models | event = EventEdit.forCreate aff }, cmd, OutMsg.Main << OutMsg.Nav <| Router.CreateEvent )

                -- XXX Hrrm. This creates a whole regime where I have to add outmsgs
                OutMsg.EditEvent creds aff ->
                    EventEdit.bidiupdate (EventEdit.Entered creds (EventEdit.Url aff.uri)) EventEdit.init
                        |> OutMsg.mapBoth (\pm -> { models | event = pm }) (Cmd.map EventEditMsg)

                OutMsg.ShowEvent creds aff ->
                    EventShow.bidiupdate (EventShow.Entered creds (EventShow.Url aff.uri)) EventShow.init
                        |> OutMsg.mapBoth (\pm -> { models | games = pm }) (Cmd.map EventShowMsg)

        _ ->
            ( models, cmd, out )
