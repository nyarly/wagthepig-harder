module ApiTests exposing (suite)

import Api

import Json.Decode as Decode exposing (Value)

import Test exposing (Test, describe, test)
import Expect exposing (..)
import Debug

suite : Test
suite =
    describe "API tests" [
        test "loadCred loads a credential" <| \_ ->
          equal (Api.loadCred dummyFlags) (Just {accountID = "user@example.com", token = "FAKETOKEN"})
    ]

dummyFlags : String
dummyFlags =
    let
        data = Decode.decodeString Decode.value "\"{\\\"accountID\\\": \\\"user@example.com\\\", \\\"token\\\": \\\"FAKETOKEN\\\"}\""
          |> Result.andThen (Decode.decodeValue Decode.string)
    in
       case data of
           Ok d -> d
           Err msg -> Debug.todo (Decode.errorToString msg)
