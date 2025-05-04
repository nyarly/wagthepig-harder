use axum::http;
use iri_string::template::{Context, UriTemplateString};
use serde::Serialize;
pub use iri_string::types::IriReferenceString;

use crate::{error::Error, routing::{self, Listable}};

#[derive(Serialize, Clone)]
#[serde(tag="type")]
pub struct IriTemplate {
    pub id: IriReferenceString,
    // pub r#type: String,
    pub template: UriTemplateString,
    pub operation: Vec<Operation>
}

#[derive(Serialize, Clone)]
#[serde(tag="type")]
pub struct Link {
    pub id: IriReferenceString,
    // pub r#type: String,
    pub operation: Vec<Operation>
}


#[derive(Default, Serialize, Clone)]
pub struct Operation {
    pub method: Method,
    pub r#type: String,
}

#[derive(Default, Clone)]
pub struct Method(http::Method);

impl From<http::Method> for Method {
    fn from(value: http::Method) -> Self {
        Self(value)
    }
}

impl Serialize for Method {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error>
    {
        serializer.serialize_str(self.0.as_str())
    }
}

#[derive(Default, Serialize, Clone)]
pub enum ActionType {
    #[default]
    #[serde(rename = "ViewAction")]
    View,
    #[serde(rename = "CreateAction")]
    Create,
    #[serde(rename = "UpdateAction")]
    Update,
    #[serde(rename = "FindAction")]
    Find,
    #[serde(rename = "AddAction")]
    Add,
    // this is not a schema.org Action type
    #[serde(rename = "LoginAction")]
    Login,
    // this is not a schema.org Action type
    #[serde(rename = "LogoutAction")]
    Logout,
}

impl std::fmt::Display for ActionType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ActionType::View => write!(f, "ViewAction"),
            ActionType::Create => write!(f, "CreateAction"),
            ActionType::Update => write!(f, "UpdateAction"),
            ActionType::Find => write!(f, "FindAction"),
            ActionType::Add => write!(f, "AddAction"),
            ActionType::Login => write!(f, "LoginAction"),
            ActionType::Logout => write!(f, "LogoutAction"),
        }
    }
}

/*
schema.org ActionType:
(note: because RDF, these cannot be exhaustive)

AchieveAction
    LoseAction
    TieAction
    WinAction
AssessAction
    ChooseAction
        VoteAction
    IgnoreAction
    ReactAction
        AgreeAction
        DisagreeAction
        DislikeAction
        EndorseAction
        LikeAction
        WantAction
    ReviewAction
ConsumeAction
    DrinkAction
    EatAction
    InstallAction
    ListenAction
    PlayGameAction
    ReadAction
    UseAction
        WearAction
    ViewAction
    WatchAction
ControlAction
    ActivateAction
    DeactivateAction
    ResumeAction
    SuspendAction
CreateAction
    CookAction
    DrawAction
    FilmAction
    PaintAction
    PhotographAction
    WriteAction
FindAction
    CheckAction
    DiscoverAction
    TrackAction
InteractAction
    BefriendAction
    CommunicateAction
        AskAction
        CheckInAction
        CheckOutAction
        CommentAction
        InformAction
            ConfirmAction
            RsvpAction
        InviteAction
        ReplyAction
        ShareAction
    FollowAction
    JoinAction
    LeaveAction
    MarryAction
    RegisterAction
    SubscribeAction
    UnRegisterAction
MoveAction
    ArriveAction
    DepartAction
    TravelAction
OrganizeAction
    AllocateAction
        AcceptAction
        AssignAction
        AuthorizeAction
        RejectAction
    ApplyAction
    BookmarkAction
    PlanAction
        CancelAction
        ReserveAction
        ScheduleAction
PlayAction
    ExerciseAction
    PerformAction
SearchAction
SeekToAction
SolveMathAction
TradeAction
    BuyAction
    OrderAction
    PayAction
    PreOrderAction
    QuoteAction
    RentAction
    SellAction
    TipAction
TransferAction
    BorrowAction
    DonateAction
    DownloadAction
    GiveAction
    LendAction
    MoneyTransfer
    ReceiveAction
    ReturnAction
    SendAction
    TakeAction
UpdateAction
    AddAction
        InsertAction
            AppendAction
            PrependAction
    DeleteAction
    ReplaceAction

* */

/// op is used to create a most-common operation for each action type
pub fn op(action: ActionType) -> Operation {
    use ActionType::*;
    use axum::http::Method;
    match action {
        View => Operation {
            method: Method::GET.into(),
            r#type: action.to_string()
        },
        Create => Operation{
            method: Method::PUT.into(),
            r#type: action.to_string()
        },
        Update => Operation{
            method: Method::PUT.into(),
            r#type: action.to_string()
        },
        Find => Operation{
            method: Method::GET.into(),
            r#type: action.to_string()
        },
        Add => Operation{
            method: Method::POST.into(),
            r#type: action.to_string()
        },
        Login => Operation{
            method: Method::POST.into(),
            r#type: action.to_string()
        },
        Logout => Operation{
            method: Method::DELETE.into(),
            r#type: action.to_string()
        }
    }
}

const RESOURCE: &str = "Resource";

#[derive(Serialize, Clone)]
pub struct ResourceType(&'static str);

impl Default for ResourceType {
    fn default() -> Self {
        Self(RESOURCE)
    }
}

#[derive(Serialize, Clone)]
pub struct ResourceFields<L: Serialize + Clone> {
    pub id: IriReferenceString,
    pub r#type: ResourceType,
    pub operation: Vec<Operation>,
    pub find_me: IriTemplate,
    pub nick: L
}

impl<L: Serialize + Clone + Listable + Context> ResourceFields<L> {
    pub fn new(route: &routing::Entry, nick: L, api_name: &str, operation: Vec<Operation>) -> Result<Self, Error> {
        let id = route.fill(nick.clone())?;
        let template = route.template()?;

        Ok(Self{
            id,
            nick,
            operation,
            r#type: Default::default(),
            find_me: IriTemplate {
                template,
                id: api_name.try_into()?,
                operation: vec![ op(ActionType::Find) ]
            },
        })
    }
}
