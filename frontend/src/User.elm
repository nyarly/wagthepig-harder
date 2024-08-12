module User exposing (User, decode)

import Json.Decode as D exposing (Decoder)

type alias User =
  { email: String
  }

decode : Decoder User
decode =
  D.map User
    (D.field "email" D.string)
