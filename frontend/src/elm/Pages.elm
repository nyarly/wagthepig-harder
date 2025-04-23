module Pages exposing (Models, Msg(..), bidiupdate, init, pageNav, view)

import Auth
import CompleteRegistration
import EventEdit
import EventShow
import Events
import Game.Create
import Game.Edit
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
    | GameCreateMsg Game.Create.Msg
    | GameEditMsg Game.Edit.Msg
    | EventShowMsg EventShow.Msg
    | RegisterMsg Register.Msg
    | CompleteRegistrationMsg CompleteRegistration.Msg



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
    , event : EventEdit.Model
    , games : EventShow.Model
    , editGame : Game.Edit.Model
    , createGame : Game.Create.Model
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
        Game.Edit.init
        Game.Create.init
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

        Router.Events sort ->
            Events.view models.events sort
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



{-
   Consider for future iterations:
   what if the router produced XXXMsg( XXX.Entered ... ) messages
   instead of Router.Page enum values

   pro: we could skip the pageNav function, because it becomes just
   Pages.bidiupdate(enteredMsg)

   cons: ?

   weird: is there a reference cycle introduced that way?
   could it be broken via OutMsg somehow?
-}


pageNav : Router.Target -> Auth.Cred -> Models -> ( Models, Cmd Msg, OutMsg.Msg )
pageNav target creds models =
    case target of
        Router.CredentialedArrival next cred ->
            ( models, Cmd.none, OutMsg.Main (OutMsg.NewCred cred next) )

        Router.Profile ->
            bidiupdate (ProfileMsg (Profile.Entered creds Profile.Creds)) models

        Router.Events sort ->
            bidiupdate (EventsMsg (Events.Entered creds sort)) models

        Router.Register ->
            bidiupdate (RegisterMsg Register.Entered) models

        Router.EventShow id ->
            bidiupdate (EventShowMsg (EventShow.Entered creds (EventShow.Nickname id))) models

        Router.CreateEvent ->
            bidiupdate (EventEditMsg (EventEdit.Entered creds EventEdit.None)) models

        Router.EventEdit id ->
            bidiupdate (EventEditMsg (EventEdit.Entered creds (EventEdit.Nickname id))) models

        Router.CreateGame ev ->
            bidiupdate (GameCreateMsg (Game.Create.Entered creds ev)) models

        Router.EditGame event_id game_id ->
            bidiupdate (GameEditMsg (Game.Edit.Entered creds event_id game_id)) models

        Router.CompleteRegistration email ->
            bidiupdate (CompleteRegistrationMsg (CompleteRegistration.Entered creds email)) models

        _ ->
            ( models, Cmd.none, OutMsg.None )



-- I wish Elm had a better way to map modules
-- fundamentally there's a pattern I want to follow here around building an interface
-- which Elm uses for App in the first place...
-- consider cribbing from Elm.Main.init({}) - is that possible?


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

        GameEditMsg submsg ->
            Game.Edit.bidiupdate submsg models.editGame
                |> OutMsg.mapBoth (\pm -> { models | editGame = pm }) (Cmd.map GameEditMsg)
                |> consumeOutmsg

        GameCreateMsg submsg ->
            Game.Create.bidiupdate submsg models.createGame
                |> OutMsg.mapBoth (\pm -> { models | createGame = pm }) (Cmd.map GameCreateMsg)
                |> consumeOutmsg


consumeOutmsg : ( Models, Cmd Msg, OutMsg.Msg ) -> ( Models, Cmd Msg, OutMsg.Msg )
consumeOutmsg ( models, cmd, out ) =
    case out of
        OutMsg.Page pagemsg ->
            case pagemsg of
                OutMsg.CreateEvent aff ->
                    ( { models | event = EventEdit.forCreate aff }, cmd, OutMsg.Main << OutMsg.Nav <| Router.CreateEvent )

        {-
           -- XXX Hrrm. This creates a whole regime where I have to add outmsgs
           OutMsg.EditEvent creds aff ->
               EventEdit.bidiupdate (EventEdit.Entered creds (EventEdit.Url aff.uri)) EventEdit.init
                   |> OutMsg.mapBoth (\pm -> { models | event = pm }) (Cmd.map EventEditMsg)
        -}
        _ ->
            ( models, cmd, out )
