module BGGAPI exposing (..)

import Hex
import Http
import Regex
import Xml.Decode exposing (Decoder, andMap, decodeString, fail, intAttr, leakyList, list, map, map2, path, requiredPath, single, string, stringAttr, succeed, with)


type Error
    = GetErr Http.Error
    | DecodeErr String


type BGGGame
    = Thing BGGThing
    | SearchResult GameResult


type alias BGGThing =
    { bggId : Int
    , name : String
    , description : String
    , minPlayers : Int
    , maxPlayers : Int
    , durationMinutes : Int
    , thumbnail : String
    }


type alias GameResult =
    { id : Int
    , name : String
    }


gameResultListDecoder : Decoder (List BGGGame)
gameResultListDecoder =
    path [ "item" ] (list gameResultDecoder)


gameResultDecoder : Decoder BGGGame
gameResultDecoder =
    map2 (\id name -> SearchResult (GameResult id name))
        (intAttr "id")
        (path [ "name" ] (single (stringAttr "value")))


requestBGGItem : (Result Error BGGThing -> msg) -> Int -> Cmd msg
requestBGGItem msg id =
    Http.get
        { url = "https://boardgamegeek.com/xmlapi2/thing?id=" ++ String.fromInt id
        , expect = Http.expectString (parseBggResult thingDecoder msg)
        }


requestBGGSearch : (Result Error (List BGGGame) -> msg) -> String -> Cmd msg
requestBGGSearch msg query =
    Http.get
        { url = "https://boardgamegeek.com/xmlapi2/search?type=boardgame,boardgameexpansion,rpgitem&query=" ++ query
        , expect = Http.expectString (parseBggResult gameResultListDecoder msg)

        --        , expect = Http.expectString (parseBggResult gameResultListDecoder GotSearchResults)
        }


parseBggResult : Decoder a -> (Result Error a -> msg) -> Result Http.Error String -> msg
parseBggResult decodes msg res =
    msg
        (case res of
            Ok body ->
                case decodeString decodes body of
                    Ok decoded ->
                        Ok decoded

                    Err err ->
                        Err (DecodeErr err)

            Err err ->
                Err (GetErr err)
        )


thingDecoder : Decoder BGGThing
thingDecoder =
    succeed BGGThing
        |> requiredPath [ "item" ] (single (intAttr "id"))
        |> andMap primaryNameDecoder
        |> requiredPath [ "item", "description" ] (single (map decodeXmlEntities string))
        |> requiredPath [ "item", "minplayers" ] (single (intAttr "value"))
        |> requiredPath [ "item", "maxplayers" ] (single (intAttr "value"))
        |> requiredPath [ "item", "maxplaytime" ] (single (intAttr "value"))
        |> requiredPath [ "item", "thumbnail" ] (single string)


primaryNameDecoder : Decoder String
primaryNameDecoder =
    map (List.head >> Maybe.withDefault "(no name)")
        (path [ "item", "name" ]
            (leakyList
                (with (stringAttr "type")
                    (\t ->
                        case t of
                            "primary" ->
                                stringAttr "value"

                            _ ->
                                fail "not primary name"
                    )
                )
            )
        )



-- gratefully stolen and expanded upon from billstclair/elm-xml-eeue56


entityRegex : Regex.Regex
entityRegex =
    Regex.fromString "&([^&;]+);" |> Maybe.withDefault Regex.never


decodeXmlEntities : String -> String
decodeXmlEntities s =
    let
        -- 0xFFFD -> <?>
        unrecognized =
            65533

        decodeEntity m =
            let
                firstSub =
                    List.head m.submatches |> Maybe.withDefault (Just "") |> Maybe.withDefault ""
            in
            case ( String.left 1 firstSub, String.slice 1 2 firstSub ) of
                ( "#", "x" ) ->
                    String.dropLeft 2 firstSub |> Hex.fromString |> Result.withDefault unrecognized |> Char.fromCode |> String.fromChar

                ( "#", _ ) ->
                    String.dropLeft 1 firstSub |> String.toInt |> Maybe.withDefault unrecognized |> Char.fromCode |> String.fromChar

                _ ->
                    case firstSub of
                        "quot" ->
                            "\""

                        "rsquo" ->
                            "'"

                        "apos" ->
                            "'"

                        "lt" ->
                            "<"

                        "gt" ->
                            ">"

                        "amp" ->
                            "&"

                        _ ->
                            m.match
    in
    Regex.replace entityRegex decodeEntity s



{-
   decodeXmlEntities : String -> String
   decodeXmlEntities s =
       List.foldl (\( x, y ) z -> String.replace ("&" ++ y ++ ";") (String.fromChar x) z) s predefinedEntities
-}


predefinedEntities : List ( Char, String )
predefinedEntities =
    -- https://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
    [ ( '"', "quot" )
    , ( '\'', "rsquo" )
    , ( '\'', "apos" )
    , ( '<', "lt" )
    , ( '>', "gt" )
    , ( '\n', "#10" )

    -- & / &amp; must come last!
    , ( '&', "amp" )
    ]
