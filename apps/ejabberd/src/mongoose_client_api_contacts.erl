-module(mongoose_client_api_contacts).

-export([init/3]).
-export([rest_init/2]).
-export([content_types_provided/2]).
-export([content_types_accepted/2]).
-export([is_authorized/2]).
-export([allowed_methods/2]).

-export([forbidden_request/2]).

-export([to_json/2]).
-export([from_json/2]).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include_lib("exml/include/exml.hrl").

init(_Transport, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, HandlerOpts) ->
    mongoose_client_api:rest_init(Req, HandlerOpts).

is_authorized(Req, State) ->
    mongoose_client_api:is_authorized(Req, State).

content_types_provided(Req, State) ->
    {[
      {{<<"application">>, <<"json">>, '*'}, to_json}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {[
      {{<<"application">>, <<"json">>, '*'}, from_json}
     ], Req, State}.

allowed_methods(Req, State) ->
    {[<<"OPTIONS">>, <<"GET">>, <<"POST">>, <<"PUT">>], Req, State}.

forbidden_request(Req, State) ->
    cowboy_req:reply(403, Req),
    {halt, Req, State}.

to_json(Req, #{jid := Caller} = State) ->
    CJid = jid:to_binary(Caller),
    {Method, _} = cowboy_req:method(Req),
    {Jid, _} = cowboy_req:binding(jid, Req),
    {ok, Res} = handle_request(Method, Jid, undefined, CJid),
    {jiffy:encode(lists:flatten([Res])), Req, State}.


from_json(Req, #{jid := Caller} = State) ->
    CJid = jid:to_binary(Caller),
    {Method, Req2} = cowboy_req:method(Req),
    {ok, Body, Req1} = cowboy_req:body(Req),
    JSONData = jiffy:decode(Body, [return_maps]),
    Jid = case maps:get(<<"jid">>, JSONData, undefined) of
              undefined ->
                  {J, _} = cowboy_req:binding(jid, Req1),
                  J;
              J -> J
          end,
    Action = maps:get(<<"action">>, JSONData, undefined),
    case handle_request(Method, to_binary(Jid), Action, CJid) of
        ok ->
            {true, Req2, State};
        not_implemented ->
            {ok, Req3} = cowboy_req:reply(501, Req2),
            {halt, Req3, State};
        not_found ->
            {ok, Req3} = cowboy_req:reply(404, Req2),
            {halt, Req3, State}
    end.

handle_request(<<"GET">>, undefined, undefined, CJid) ->
    mongoose_commands:execute(CJid, list_contacts, #{caller => CJid});
handle_request(<<"POST">>, Jid, undefined, CJid) ->
    mongoose_commands:execute(CJid, add_contact, #{caller => CJid,
        jid => Jid});
handle_request(Method, Jid, Action, CJid) ->
    case jid_exists(CJid, Jid) of
        true -> handle_contact_request(Method, Jid, Action, CJid);
        false -> not_found
    end.

handle_contact_request(<<"PUT">>, Jid, <<"invite">>, CJid) ->
    mongoose_commands:execute(CJid, subscription, #{caller => CJid,
        jid => Jid, action => <<"subscribe">>});
handle_contact_request(<<"PUT">>, Jid, <<"accept">>, CJid) ->
    mongoose_commands:execute(CJid, subscription, #{caller => CJid,
        jid => Jid, action => <<"subscribed">>});
handle_contact_request(_, _, _, _) ->
    not_implemented.

to_binary(S) when is_binary(S) ->
    S;
to_binary(S) ->
    list_to_binary(S).

-spec jid_exists(binary(), binary()) -> boolean().
jid_exists(CJid, Jid) ->
    {ok, Roster} = mongoose_commands:execute(CJid, list_contacts,
                                             #{caller => CJid}),
    Res = lists:filter(
        fun(M) -> maps:get(jid, M, undefined) == Jid end,
        Roster),
    Res =/= [].

