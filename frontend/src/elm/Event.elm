module Event exposing (..)

import Dict
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Time


nickToVars : Int -> Dict.Dict String String
nickToVars id =
    Dict.fromList [ ( "event_id", String.fromInt id ) ]


browseToEvent : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToEvent vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [] (ByType "FindAction") |> HM.fillIn vars
    ]


formatTime : { a | time : Time.Posix } -> String
formatTime event =
    -- Thu Mar 31, 2024
    formatWeekday event.time
        ++ " "
        ++ formatMonth event.time
        ++ " "
        ++ String.fromInt
            (Time.toDay Time.utc event.time)
        ++ ", "
        ++ String.fromInt (Time.toYear Time.utc event.time)


formatWeekday : Time.Posix -> String
formatWeekday posix =
    case Time.toWeekday Time.utc posix of
        Time.Mon ->
            "Mon"

        Time.Tue ->
            "Tue"

        Time.Wed ->
            "Wed"

        Time.Thu ->
            "Thu"

        Time.Fri ->
            "Fri"

        Time.Sat ->
            "Sat"

        Time.Sun ->
            "Sun"


formatMonth : Time.Posix -> String
formatMonth posix =
    case Time.toMonth Time.utc posix of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"
