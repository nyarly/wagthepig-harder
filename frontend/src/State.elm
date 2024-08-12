port module State exposing (
  store, clear,
  onStoreChange, loadAll, asString)

import Json.Decode as D exposing (Value)
import Dict exposing (Dict)

asString : Value -> Maybe String
asString value =
  D.decodeValue D.string value
  |> Result.toMaybe

store : String -> Value -> Cmd msg
store name value =
  storeCache (name, Just value)

clear : String -> Cmd msg
clear name =
  storeCache (name, Nothing)

loadAll : Value -> Result D.Error (Dict String Value)
loadAll localValues =
  D.decodeValue (D.dict D.value) localValues

port storeCache : (String, Maybe Value) -> Cmd msg

port onStoreChange : ((String, Value) -> msg) -> Sub msg
