module Players exposing (OtherPlayers(..), Player, closeOtherPlayers, otherPlayersDecoder, playerDecoder, playerName)

import Hypermedia exposing (Uri, decodeMaybe)
import Json.Decode as D
import Json.Decode.Pipeline exposing (required)


type alias Player =
    { id : Uri
    , name : Maybe String
    , bgg_username : Maybe String
    , email : String
    }


playerDecoder : D.Decoder Player
playerDecoder =
    D.succeed Player
        |> required "id" D.string
        |> decodeMaybe "name" D.string
        |> decodeMaybe "bgg_username" D.string
        |> required "email" D.string


playerName : Player -> String
playerName player =
    case player.name of
        Just name ->
            name

        Nothing ->
            case player.bgg_username of
                Just bname ->
                    bname

                Nothing ->
                    player.email


type OtherPlayers
    = Empty
    | Open (List Player)
    | Closed (List Player)


otherPlayersDecoder : D.Decoder OtherPlayers
otherPlayersDecoder =
    D.succeed Open
        |> required "users" (D.list playerDecoder)


closeOtherPlayers : OtherPlayers -> OtherPlayers
closeOtherPlayers ops =
    case ops of
        Open list ->
            Closed list

        _ ->
            ops
