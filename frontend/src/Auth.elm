module Auth exposing (Cred, unauthenticated, loggedIn, storageField, loadCred, storeCred, fragmentParser, credExtractor, credHeader, accountID, logout, testSuite)

import Http
import Dict exposing (Dict)
import Json.Decode as D exposing (Decoder, Value)
import Json.Encode as E

import State

-- testing
import Test as T
import Expect exposing (equal)
import Url.Parser as P exposing (Parser)

{-
-- CRED
This token should never be rendered to the end user, and with
Cred as an opaque type, it can't be
-}
type Cred =
  Cred (Maybe Credentials)

type alias Credentials =
  { accountID: String
  , token: String
  }

type alias Headers = (Dict String String)

unauthenticated : Cred
unauthenticated =
  Cred Nothing

loggedIn : Cred -> Bool
loggedIn (Cred cred) =
  case cred of
    Just _ -> True
    Nothing -> False

storageField : String
storageField =
  "credentials"

loadCred : String -> Cred
loadCred value =
  D.decodeString credDecoder value
  |> Result.mapError D.errorToString
  |> Debug.log "loaded cred"
  |> Result.toMaybe
  |> Cred

credHeader : Cred-> List(Http.Header)
credHeader (Cred cred) =
  case cred of
    Just c->
      [ Http.header "authorization" c.token ] -- Should be something like: ("Token " ++ cred.token)
    Nothing ->
      []


{-| It's important that this is never exposed!
We expose `login`, `loadCred` and request functions instead, so we can be certain that if anyone
ever has access to a `Cred` value, it came from either the login API endpoint
or was passed in via flags.
-}
credDecoder : Decoder Credentials
credDecoder =
  D.map2 Credentials
    (D.field "accountID" D.string)
    (D.field "token" D.string)

fragmentParser : Parser (Cred -> a) a
fragmentParser =
  P.map anonymousToken (P.fragment identity)

anonymousToken :  Maybe String -> Cred
anonymousToken maybeToken = -- XXX should use the body to get accountID
  case maybeToken of
    Just token -> Cred( Just( Credentials "" token ))
    Nothing -> Cred( Nothing )


encodeCred : Credentials -> Value
encodeCred cred =
  E.object
  [ ("accountID", E.string cred.accountID )
  , ("token", E.string cred.token )
  ]

storeCred : Cred -> Cmd msg
storeCred (Cred cred) =
  case cred of
    Just c -> State.store storageField (encodeCred c)
    Nothing -> State.clear storageField

credExtractor : String -> {res | headers: Headers} -> (Result String Cred)
credExtractor email res = -- XXX should use the body to get accountID
  case (Dict.get "set-authorization" res.headers) of
    Just token -> Ok (Cred (Just (Credentials email token)))
    Nothing -> Err "no set-authorization header"

accountID : Cred -> String
accountID (Cred cred) =
  case cred of
    Just c -> c.accountID
    Nothing -> ""

-- XXX
-- Need to DELETE the authentication
logout : Cmd msg
logout =
  State.clear storageField


testSuite : T.Test
testSuite =
    T.describe "API tests" [
        T.test "loadCred loads a credential" <| \_ ->
          equal (loadCred dummyFlags) (Cred (Just {accountID = "user@example.com", token = "FAKETOKEN"}))
    ]

dummyFlags : String
dummyFlags =
    let
        data = D.decodeString D.value "\"{\\\"accountID\\\": \\\"user@example.com\\\", \\\"token\\\": \\\"FAKETOKEN\\\"}\""
          |> Result.andThen (D.decodeValue D.string)
    in
       case data of
           Ok d -> d
           Err msg -> Debug.todo (D.errorToString msg)
