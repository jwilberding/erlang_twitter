%% Copyright (c) 2008 Nick Gerakines <nick@gerakines.net>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
%% 
%% @author Nick Gerakines <nick@gerakines.net>
%% @copyright 2008-2009 Nick Gerakines
%% @version 0.4
%% @doc Provides access to the Twitter web service. Mostly through the
%% clever use of REST-like requests and XML parsing.
%% 
%% This module attempts to provide complete access to the Twitter API. In
%% addition, it provides a simple gen_server process template to allow calls
%% to be made on behalf of a named user without having to send a username
%% and password each time.
%% 
%% When the gen_server feature is used to make Twitter API calls for a user,
%% a gen_server process is spawned locally and its name is prefixed to
%% prevent named process collision.
%% 
%% <strong>Make sure you start inets (<code>inets:start().</code>) before you do
%% anything.</strong>
%% 
%% <h4>Quick start</h4>
%% <pre><code>
%% 1&gt; inets:start().
%% 2&gt; twitter_client:start("myname", "pass").
%% 3&gt; twitter_client:account_verify_credentials("myname", "pass", []).
%%   OR
%% 3&gt; twitter_client:call("myname", account_verify_credentials).
%% 4&gt; twitter_client:call("myname", user_timeline).
%% 5&gt; twitter_client:call("myname", status_update, [{"status", "Testing the erlang_twitter twitter_client.erl library."}]).
%% 6&gt; twitter_client:call("myname", user_timeline).
%% </code></pre>
-module(twitter_client).
-behaviour(gen_server).

-author("Nick Gerakines <nick@gerakines.net>").
-version("0.5").

-export([
    init/1, terminate/2, code_change/3,
    handle_call/3, handle_cast/2, handle_info/2
]).

-export([
    status_friends_timeline/2,
    status_home_timeline/2,
    status_user_timeline/2,
    status_mentions/2,
    status_show/2,
    status_update/2,
    status_replies/2,
    status_destroy/2,
    account_archive/2, collect_account_archive/4,
    account_update_location/2,
    account_update_delivery_device/2,
    account_rate_limit_status/2,
    direct_messages/2, collect_direct_messages/4,
    direct_new/2,
    direct_sent/2,
    direct_destroy/2,
account_end_session/4, 
account_verify_credentials/4, 
account_verify_credentials/5, add_session/2, block_create/4, block_create/5, 
block_destroy/4, block_destroy/5, build_url/2, call/2, call/3,
collect_favorites/5, collect_favorites/6, collect_user_friends/5,
collect_user_friends/6, collect_user_followers/5, collect_user_followers/6,
exists_session/1, favorites_create/4, favorites_create/5,
favorites_destroy/4, favorites_destroy/5, favorites_favorites/4, favorites_favorites/5,
friendship_create/4, friendship_create/5, friendship_destroy/4, friendship_destroy/5,
friendship_exists/4, friendship_exists/5, headers/2, help_test/4, info/0,
notification_follow/4, notification_follow/5, notification_leave/4, notification_leave/5,
parse_status/1, parse_statuses/1, parse_user/1, parse_users/1, request_url/5, 
session_from_client/2, set/2, start/0, social_graph_friend_ids/4, social_graph_friend_ids/6,
social_graph_follower_ids/4, social_graph_follower_ids/6,
text_or_default/3, user_featured/4, user_followers/4, user_followers/5, user_friends/4, 
user_friends/5, user_show/4, user_show/5, delay/0]).

-include("twitter_client.hrl").
-include_lib("xmerl/include/xmerl.hrl").

-record(erlang_twitter, {sessions, base_url, delay, lastcall}).

-define(BASE_URL(X), "http://www.twitter.com/" ++ X).

%% @spec start() -> Result
%% where 
%%       Result = {ok, pid()} | Error
%% @doc Start a twitter_client gen_server process for a Twitter user.
start() ->
    inets:start(),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @spec add_session(Login, Password) -> ok
%% where 
%%       Login = string()
%%       Password = string()
%% @doc Start a twitter_client gen_server process for a Twitter user.
add_session(Login, Password) ->
    gen_server:call(?MODULE, {add_session, Login, Password}, infinity).

%% @spec exists_session(Login) -> true | false
%%       Login = string()
%% @doc Determines if a login is know by the twitter client.
exists_session(Login) ->
    gen_server:call(?MODULE, {exists_session, Login}, infinity).

%% @spec set(Type, Value) -> Response
%%       Type = base_url | delay
%%       value = any()
%%       Response = any()
%% @doc Sets a configuration value in the twitter client.
set(base_url, Value) ->
    gen_server:call(?MODULE, {base_url, Value}, infinity);

set(delay, Value) ->
    gen_server:call(?MODULE, {delay, Value}, infinity).

%% @doc Returns information on the twitter client.
info() ->
    gen_server:call(?MODULE, {info}, infinity).

delay() ->
    gen_server:call(?MODULE, {should_wait}, infinity).    

%% @equiv call(Client, Method, [])
call(Client, Method) ->
    twitter_client:call(Client, Method, []).

%% @spec call(Client, Method, Args) -> Result
%% where 
%%       Client = string() | atom()
%%       Method = atom()
%%       Args = [{any(), any()}]
%%       Result = any()
%% @doc Make a request to a twitter_client gen_server process for a user.
%% This function attempts to call the named gen_server process for the given
%% client (usern). The method called maps directly to the available methods
%% provided by this module. Please refer to the specific methods for their
%% required and optional arguments. In most (all) cases the arguments
%% defined in the Twitter API documentation can be passed in directly as
%% string/string tuples.
%% 
%% Calling this method does not verify that the given gen_server process
%% exists or is running.
call(Client, Method, Args) ->
    gen_server:call(?MODULE, {Client, Method, Args}, infinity).

%% @private
init(_) ->
    {ok, #erlang_twitter{
        sessions = gb_trees:empty(),
        base_url = "http://twitter.com/",
        delay = 0,
        lastcall = calendar:datetime_to_gregorian_seconds(erlang:universaltime())
    }}.

%% @private
session_from_client(State, Client) ->
    case gb_trees:is_defined(Client, State#erlang_twitter.sessions) of
        false -> {error, invalid_client};
        true -> gb_trees:get(Client, State#erlang_twitter.sessions)
    end.

%% @private
handle_call({base_url, BaseUrl}, _From, State) ->
    {reply, ok, State#erlang_twitter{ base_url = BaseUrl }};

handle_call({delay, Delay}, _From, State) ->
    {reply, ok, State#erlang_twitter{ delay = Delay }};

handle_call({should_wait}, _From, State) ->
    Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),
    Delay = case State#erlang_twitter.delay of
        0 -> 0;
        Time when Time + State#erlang_twitter.delay < Now -> 0;
        _ -> State#erlang_twitter.delay
    end,
    {reply, Delay, State};

handle_call({add_session, Login, Password}, _From, State) ->
    NewTree =  case gb_trees:is_defined(Login, State#erlang_twitter.sessions) of
        true -> State#erlang_twitter.sessions;
        false -> gb_trees:insert(Login, {Login, Password}, State#erlang_twitter.sessions)
    end,
    {reply, ok, State#erlang_twitter{ sessions = NewTree }};

handle_call({remove_session, Login}, _From, State) ->
    NewTree =  case gb_trees:is_defined(Login, State#erlang_twitter.sessions) of
        true -> gb_trees:delete(Login, State#erlang_twitter.sessions);
        false -> State#erlang_twitter.sessions
    end,
    {reply, ok, State#erlang_twitter{ sessions = NewTree }};

handle_call({exists_session, Login}, _From, State) ->
    {reply, gb_trees:is_defined(Login, State#erlang_twitter.sessions), State};

handle_call({info}, _From, State) ->
    {reply, State, State};

handle_call({Client, collect_direct_messages, LowId}, _From, State) ->
    Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),
    Response = case session_from_client(State, Client) of
        {error, Reason} -> {error, Reason};
        {Login, Password} ->
            twitter_client:collect_direct_messages(State#erlang_twitter.base_url, Login, Password, 1, LowId, []);
        _ -> {error, unknown}
    end,
    {reply, Response, State#erlang_twitter{ lastcall = Now }};

handle_call({Client, collect_user_friends, _Args}, _From, State) ->
    Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),
    Response = case session_from_client(State, Client) of
        {error, Reason} -> {error, Reason};
        {Login, Password} ->
            twitter_client:collect_user_friends(State#erlang_twitter.base_url, Login, Password, 1, []);
        _ -> {error, unknown}
    end,
    {reply, Response, State#erlang_twitter{ lastcall = Now }};

handle_call({Client, collect_user_followers, _Args}, _From, State) ->
    Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),
    Response = case session_from_client(State, Client) of
        {error, Reason} -> {error, Reason};
        {Login, Password} ->
            twitter_client:collect_user_followers(State#erlang_twitter.base_url, Login, Password, 1, []);
        _ -> {error, unknown}
    end,
    {reply, Response, State#erlang_twitter{ lastcall = Now }};

handle_call({Client, Method, Args}, _From, State) ->
    Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),
    Response = case session_from_client(State, Client) of
        {error, Reason} -> {error, Reason};
        {Login, Password} ->
            try apply(twitter_client, Method, [State#erlang_twitter.base_url, Login, Password, Args])
            catch
                _X:_Y -> {error, unsupported_method}
            end;
        _ -> {error, unknown}
    end,
    {reply, Response, State#erlang_twitter{ lastcall = Now }};

handle_call(stop, _From, State) -> {stop, normalStop, State};

handle_call(_, _From, State) -> {noreply, ok, State}.

%% @private
handle_cast(_Msg, State) -> {noreply, State}.

%% @private
handle_info(_Info, State) -> {noreply, State}.

%% @private
terminate(_Reason, _State) -> ok.

%% @private
code_change(_OldVsn, State, _Extra) -> {ok, State}.

status_home_timeline(Auth, Args) when is_tuple(Auth), is_list(Args) ->
    Url = build_url("statuses/home_timeline.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

status_friends_timeline(Auth, Args) when is_tuple(Auth), is_list(Args) ->
    Url = case lists:keytake("id", 1, Args) of 
        false -> build_url("statuses/friends_timeline" ++ ".xml", Args);
        {_, {"id", Id}, RetArgs} -> build_url("statuses/friends_timeline" ++ "/" ++ Id ++ ".xml", RetArgs)
    end,
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

status_user_timeline(Auth, Args) ->
    Url = case lists:keytake("id", 1, Args) of 
        false -> build_url("statuses/user_timeline" ++ ".xml", Args);
        {_, {"id", Id}, RetArgs} -> build_url("statuses/user_timeline" ++ "/" ++ Id ++ ".xml", RetArgs)
    end,
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

status_mentions(Auth, Args) ->
    Url = build_url("statuses/mentions.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

status_show(Auth, [{"id", Id}]) ->
    Url = build_url("statuses/show/" ++ Id ++ ".xml", []),
    request_url(get, Url, Auth, [], fun(X) -> parse_status(X) end).

status_update(Auth, Args) ->
    request_url(post, "statuses/update.xml", Auth, Args, fun(X) -> parse_status(X) end).

status_replies(Auth, Args) ->
    Url = build_url("statuses/replies.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

status_destroy(Auth, [{"id", Id}]) ->
    Url = build_url("statuses/destroy/" ++ Id ++ ".xml", []),
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

%% % -
%% % Account API methods

account_verify_credentials(RootUrl, Login, Password, _) ->
    Url = build_url(RootUrl ++ "account/verify_credentials.xml", []),
    case http:request(get, {Url, headers(Login, Password)}, [], []) of
        {ok, {{_HTTPVersion, 200, _Text}, _Headers, _Body}} -> true;
        {ok, {{_HTTPVersion, 401, _Text}, _Headers, _Body}} -> false;
        _ -> {error}
    end.
account_verify_credentials(RootUrl, Consumer, Token, Secret, _) ->
    Url = build_url(RootUrl ++ "account/verify_credentials.xml", []),
    case oauth:get(Url, [], Consumer, Token, Secret) of
        {ok, {{_HTTPVersion, 200, _Text}, _Headers, _Body}} -> true;
        {ok, {{_HTTPVersion, 401, _Text}, _Headers, _Body}} -> false;
        _ -> {error}
    end.

account_end_session(RootUrl, Login, Password, _) ->
    Url = build_url(RootUrl ++ "account/end_session", []),
    request_url(get, Url, Login, Password, nil).

account_archive(Auth, Args) ->
    Url = build_url("account/archive.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_statuses(X) end).

collect_account_archive(Auth, Page, Args, Acc) ->
    NArgs = [{"page", integer_to_list(Page)} ] ++ Args,
    Messages = twitter_client:account_archive(Auth, NArgs),
    %% NKG: Assert that `Messages` is a list?
    case length(Messages) of
        80 -> collect_account_archive(Auth, Page + 1, Args, [Messages | Acc]);
        0 -> lists:flatten(Acc);
        _ -> lists:flatten([Messages | Acc])
    end.

account_update_location(Auth, Args) ->
    Url = build_url("account/update_location.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_user(X) end).

account_update_delivery_device(Auth, Args) ->
    Url = build_url("account/update_delivery_device.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_user(X) end).

account_rate_limit_status(Auth, Args) ->
    Url = build_url("account/rate_limit_status.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_rate_limit(X) end).

direct_messages(Auth, Args) ->
    Url = build_url("direct_messages.xml", Args),
    request_url(get, Url, Auth, [], fun(X) -> parse_messages(X) end).

collect_direct_messages(Auth, Page, LowID, Acc) ->
    Args = [{"page", integer_to_list(Page)}, {"since_id", integer_to_list(LowID)}],
    Messages = twitter_client:direct_messages(Auth, Args),
    %% NKG: Assert that `Messages` is a list?
    case length(Messages) of
        20 -> collect_direct_messages(Auth, Page + 1, LowID, [Messages | Acc]);
        0 -> lists:flatten(Acc);
        _ -> lists:flatten([Messages | Acc])
    end.

direct_new(Auth, Args) ->
    request_url(post, "direct_messages/new.xml", Auth, Args, fun(Body) -> parse_message(Body) end).

direct_sent(Auth, Args) ->
    Url = build_url("direct_messages/sent.xml", Args),
    request_url(get, Url, Auth, [], fun(Body) -> parse_messages(Body) end).

direct_destroy(Auth, [{"id", Id}]) ->
    Url = build_url("direct_messages/destroy/" ++ Id ++ ".xml", []),
    request_url(get, Url, Auth, [], fun(Body) -> parse_status(Body) end).

%% % -
%% % Favorites API methods

favorites_favorites(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "favorites",
    Url = case lists:keytake("id", 1, Args) of 
        false ->
            build_url(UrlBase ++ ".xml", Args);
        {value, {"id", Id}, RetArgs} ->
            build_url(UrlBase ++ "/" ++ Id ++ ".xml", RetArgs)
    end,
    Body = request_url(get, Url, Login, Password, nil),
    parse_statuses(Body).
favorites_favorites(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "favorites",
    Url = case lists:keytake("id", 1, Args) of 
        false ->
            UrlBase ++ ".xml";
        {value, {"id", Id}, _RetArgs} ->
            UrlBase ++ "/" ++ Id ++ ".xml"
    end,
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, Args),
    parse_statuses(Body).

collect_favorites(RootUrl, Login, Password, Page, Acc) ->
    Args = [{"page", integer_to_list(Page)}],
    Messages = twitter_client:favorites_favorites(RootUrl, Login, Password, Args),
    case length(Messages) of
        20 -> collect_favorites(RootUrl, Login, Password, Page + 1, [Messages | Acc]);
        0 -> lists:flatten(Acc);
        _ -> lists:flatten([Messages | Acc])
    end.
collect_favorites(RootUrl, Consumer, Token, Secret, Page, Acc) ->
    Args = [{"page", integer_to_list(Page)}],
    Messages = twitter_client:favorites_favorites(RootUrl, Consumer, Token, Secret, Args),
    case length(Messages) of
        20 -> collect_favorites(RootUrl, Consumer, Token, Secret, Page + 1, [Messages | Acc]);
        0 -> lists:flatten(Acc);
        _ -> lists:flatten([Messages | Acc])
    end.

favorites_create(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "favorites/create/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            parse_status(Body);
        _ -> {error}
    end.
favorites_create(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "favorites/create/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            parse_status(Body);
        _ -> {error}
    end.

favorites_destroy(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "favorites/destroy/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            parse_status(Body);
        _ -> {error}
    end.
favorites_destroy(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "favorites/destroy/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            parse_status(Body);
        _ -> {error}
    end.

%% % -
%% % Friendship API methods

friendship_exists(RootUrl, Login, Password, Args) ->
    Url = build_url(RootUrl ++ "friendships/exists.xml", Args),
    Body = request_url(get, Url, Login, Password, nil),
    Body == "<friends>true</friends>".
friendship_exists(RootUrl, Consumer, Token, Secret, Args) ->
    Url = RootUrl ++ "friendships/exists.xml",
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, Args),
    Body == "<friends>true</friends>".

friendship_create(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "friendships/create/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = request_url(post, Url, Login, Password, Args),
            parse_user(Body);
        _ -> {error}
    end.
friendship_create(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "friendships/create/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(post, Url, Consumer, Token, Secret, Args),
            parse_user(Body);
        _ -> {error}
    end.

friendship_destroy(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "friendships/destroy/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            parse_user(Body);
        _ -> {error}
    end.
friendship_destroy(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "friendships/destroy/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            parse_user(Body);
        _ -> {error}
    end.
%% % -
%% % User API methods

user_friends(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "statuses/friends",
    Url = case lists:keytake("id", 1, Args) of 
        false ->
            build_url(UrlBase ++ ".xml", Args);
        {value, {"id", Id}, RetArgs} ->
            build_url(UrlBase ++ "/" ++ Id ++ ".xml", RetArgs)
    end,
    Body = request_url(get, Url, Login, Password, nil),
    parse_users(Body).
user_friends(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "statuses/friends",
    Url = case lists:keytake("id", 1, Args) of 
        false ->
            UrlBase ++ ".xml";
        {value, {"id", Id}, _RetArgs} ->
            UrlBase ++ "/" ++ Id ++ ".xml"
    end,
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, Args),
    parse_users(Body).

collect_user_friends(RootUrl, Login, Password, Page, Acc) ->
    Friends = twitter_client:user_friends(RootUrl, Login, Password, [{"page", integer_to_list(Page)}, {"lite", "true"}]),
    case length(Friends) of
      100 -> collect_user_friends(RootUrl, Login, Password, Page + 1, [Friends | Acc]);
      0 -> lists:flatten(Acc);
      _ -> lists:flatten([Friends | Acc])
    end.
collect_user_friends(RootUrl, Consumer, Token, Secret, Page, Acc) ->
    Friends = twitter_client:user_friends(RootUrl, Consumer, Token, Secret, [{"page", integer_to_list(Page)}, {"lite", "true"}]),
    case length(Friends) of
      100 -> collect_user_friends(RootUrl, Consumer, Token, Secret, Page + 1, [Friends | Acc]);
      0 -> lists:flatten(Acc);
      _ -> lists:flatten([Friends | Acc])
    end.

user_followers(RootUrl, Login, Password, Args) ->
    Url = build_url(RootUrl ++ "statuses/followers.xml", Args),
    Body = request_url(get, Url, Login, Password, nil),
    parse_users(Body).
user_followers(RootUrl, Consumer, Token, Secret, Args) ->
    Url = RootUrl ++ "statuses/followers.xml",
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, Args),
    parse_users(Body).

collect_user_followers(RootUrl, Login, Password, Page, Acc) ->
    Followers = twitter_client:user_followers(RootUrl, Login, Password, [{"page", integer_to_list(Page)}, {"lite", "true"}]),
    case length(Followers) of
        100 -> collect_user_followers(RootUrl, Login, Password, Page + 1, [Followers | Acc]);
        0 -> lists:flatten(Acc);
        _ -> lists:flatten([Followers | Acc])
    end.
collect_user_followers(RootUrl, Consumer, Token, Secret, Page, Acc) ->
    Followers = twitter_client:user_followers(RootUrl, Consumer, Token, Secret, [{"page", integer_to_list(Page)}, {"lite", "true"}]),
    case length(Followers) of
        100 -> collect_user_followers(RootUrl, Consumer, Token, Secret, Page + 1, [Followers | Acc]);
        0 -> lists:flatten(Acc);
        _ -> lists:flatten([Followers | Acc])
    end.

user_featured(RootUrl, _, _, _) ->
    Url = build_url(RootUrl ++ "statuses/featured.xml", []),
    Body = request_url(get, Url, nil, nil, nil),
    parse_users(Body).

user_show(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "users/show",
    Url = case lists:keytake("id", 1, Args) of 
        false ->
            build_url(UrlBase ++ ".xml", Args);
        {value, {"id", Id}, RetArgs} ->
            build_url(UrlBase ++ "/" ++ Id ++ ".xml", RetArgs)
    end,
    Body = request_url(get, Url, Login, Password, nil),
    case Body of
      {error, Error} -> {error, Error};
      _ -> parse_user(Body)
    end.
user_show(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "users/show",
    Url = case lists:keytake("id", 1, Args) of 
        false ->
            UrlBase ++ ".xml";
        {value, {"id", Id}, _RetArgs} ->
            UrlBase ++ "/" ++ Id ++ ".xml"
    end,
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, Args),
    case Body of
      {error, Error} -> {error, Error};
      _ -> parse_user(Body)
    end.

%% % -
%% % Notification API methods

notification_follow(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "notifications/follow/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.
notification_follow(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "notifications/follow/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.

notification_leave(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "notifications/leave/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.
notification_leave(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "notifications/leave/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.

%% % -
%% % Block API methods

block_create(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "blocks/create/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.
block_create(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "blocks/create/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.

block_destroy(RootUrl, Login, Password, Args) ->
    UrlBase = RootUrl ++ "blocks/destroy/",
    case Args of
        [{"id", Id}] ->
            Url = build_url(UrlBase ++ Id ++ ".xml", []),
            Body = request_url(get, Url, Login, Password, nil),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.
block_destroy(RootUrl, Consumer, Token, Secret, Args) ->
    UrlBase = RootUrl ++ "blocks/destroy/",
    case Args of
        [{"id", Id}] ->
            Url = UrlBase ++ Id ++ ".xml",
            Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
            case parse_user(Body) of [#user{ screen_name = Id }] -> true; _ -> false end;
        _ -> {error}
    end.

%% % -
%% % Help API methods

help_test(RootUrl, _, _, _) ->
    Url = build_url(RootUrl ++ "help/test.xml", []),
    Body = request_url(get, Url, nil, nil, nil),
    Body == "<ok>true</ok>".
    
%% % -
%% % Social Graph API Methods

social_graph_friend_ids(RootUrl, Login, Password, _Args) ->
    Url = build_url(RootUrl ++ "friends/ids/" ++ twitter_client_utils:url_encode(Login) ++ ".xml", []),
    Body = request_url(get, Url, Login, Password, nil),
    parse_ids(Body).
social_graph_friend_ids(RootUrl, Login, Consumer, Token, Secret, _Args) ->
    Url = RootUrl ++ "friends/ids/" ++ twitter_client_utils:url_encode(Login) ++ ".xml",
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
    parse_ids(Body).

social_graph_follower_ids(RootUrl, Login, Password, _Args) ->
    Url = build_url(RootUrl ++ "followers/ids/" ++ twitter_client_utils:url_encode(Login) ++ ".xml", []),
    Body = request_url(get, Url, Login, Password, nil),
    parse_ids(Body).
social_graph_follower_ids(RootUrl, Login, Consumer, Token, Secret, _Args) ->
    Url = RootUrl ++ "followers/ids/" ++ twitter_client_utils:url_encode(Login) ++ ".xml",
    Body = oauth_request_url(get, Url, Consumer, Token, Secret, []),
    parse_ids(Body).

%% @private
build_url(Url, []) -> Url;
build_url(Url, Args) ->
    Url ++ "?" ++ lists:concat(
        lists:foldl(
            fun (Rec, []) -> [Rec]; (Rec, Ac) -> [Rec, "&" | Ac] end, [],
            [K ++ "=" ++ twitter_client_utils:url_encode(V) || {K, V} <- Args]
        )
    ).

request_url(get, Url, {Login, Pass}, _, Fun) ->
    case http:request(get, {?BASE_URL(Url), headers(Login, Pass)}, [{timeout, 6000}], []) of
        {ok, {_, _, Body}} -> Fun(Body);
        Other -> {error, Other}
    end;
request_url(post, Url, {Login, Pass}, Args, Fun) ->
    Body = twitter_client_utils:compose_body(Args),
    case http:request(post, {?BASE_URL(Url), headers(Login, Pass), "application/x-www-form-urlencoded", Body} , [{timeout, 6000}], []) of
        {ok, {_, _, Body2}} -> Fun(Body2);
        Other -> {error, Other}
    end;
request_url(get, Url, {Consumer, Token, Secret}, Args, Fun) ->
    case oauth:get(?BASE_URL(Url), Args, Consumer, Token, Secret) of
        {ok, {_, _, "Failed to validate oauth signature or token"}} -> {oauth_error, "Failed to validate oauth signature or token"};
        {ok, {_, _, Body}} -> Fun(Body);
        Other -> Other
    end;
request_url(post, Url, {Consumer, Token, Secret}, Args, Fun) ->
    case oauth:post(?BASE_URL(Url), Args, Consumer, Token, Secret) of
        {ok, {_, _, "Failed to validate oauth signature or token"}} -> {oauth_error, "Failed to validate oauth signature or token"};
        {ok, {_, _, Body}} -> Fun(Body);
        Other -> Other
    end;

%% @private
request_url(get, Url, Login, Pass, _) ->
    HTTPResult = http:request(get, {Url, headers(Login, Pass)}, [{timeout, 6000}], []),
    case HTTPResult of
        {ok, {_Status, _Headers, Body}} -> Body;
        _ -> {error, HTTPResult}
    end;

request_url(post, Url, Login, Pass, Args) ->
    Body = lists:concat(
        lists:foldl(
            fun (Rec, []) -> [Rec]; (Rec, Ac) -> [Rec, "&" | Ac] end,
            [],
            [K ++ "=" ++ twitter_client_utils:url_encode(V) || {K, V} <- Args]
        )
    ),
    HTTPResult = http:request(post, {Url, headers(Login, Pass), "application/x-www-form-urlencoded", Body} , [{timeout, 6000}], []),
    case HTTPResult of
        {ok, {_Status, _Headers, Body2}} -> Body2;
        _ -> {error, HTTPResult}
    end.

%% @private
oauth_request_url(get, Url, Consumer, Token, Secret, Args) ->
    HTTPResult = oauth:get(Url, Args, Consumer, Token, Secret),
    case HTTPResult of
        {ok, {_Status, _Headers, "Failed to validate oauth signature or token"}} -> {oauth_error, "Failed to validate oauth signature or token"};
        {ok, {_Status, _Headers, Body}} -> Body;
        _ -> HTTPResult
    end;

oauth_request_url(post, Url, Consumer, Token, Secret, Args) ->
    HTTPResult = oauth:post(Url, Args, Consumer, Token, Secret),
    case HTTPResult of
        {ok, {_Status, _Headers, "Failed to validate oauth signature or token"}} -> {oauth_error, "Failed to validate oauth signature or token"};
        {ok, {_Status, _Headers, Body}} -> Body;
        _ -> HTTPResult
    end.

%% @private
headers(nil, nil) -> [{"User-Agent", "ErlangTwitterClient/0.1"}];
headers(User, Pass) when is_binary(User) ->
    headers(binary_to_list(User), Pass);
headers(User, Pass) when is_binary(Pass) ->
    headers(User, binary_to_list(Pass));
headers(User, Pass) ->
    UP = base64:encode(User ++ ":" ++ Pass),
    Basic = lists:flatten(io_lib:fwrite("Basic ~s", [UP])),
    [{"User-Agent", "ErlangTwitterClient/0.1"}, {"Authorization", Basic}, {"Host", "twitter.com"}].

%% % -
%% % Response parsing functions

%% @private
parse_statuses(Body) ->
    case (catch xmerl_scan:string(Body, [{quiet, true}])) of
        {'EXIT', _} -> {error, Body};
        {error, _} -> {error, Body};
        Result ->
            {Xml, _Rest} = Result,
            [parse_status(Node) || Node <- lists:flatten([xmerl_xpath:string("/statuses/status", Xml), xmerl_xpath:string("/direct-messages/direct_message", Xml)])]
    end.

%% @private
parse_ids(Body) ->
    case (catch xmerl_scan:string(Body, [{quiet, true}])) of
        {'EXIT', _} -> {error, Body};
        {error, _} -> {error, Body};
        Result ->
            {Xml, _Rest} = Result,
            [parse_id(Node) || Node <- xmerl_xpath:string("/ids/id", Xml)]
    end.
    
%% @private
parse_status(Node) when is_tuple(Node) ->
    Status = #status{
        created_at = text_or_default(Node, ["/status/created_at/text()", "/direct_message/created_at/text()"], ""),
        id = text_or_default(Node, ["/status/id/text()", "/direct_message/id/text()"], ""),
        text = text_or_default(Node, ["/status/text/text()", "/direct_message/text/text()"], ""),
        source = text_or_default(Node, ["/status/source/text()", "/direct_message/source/text()"], ""),
        truncated = text_or_default(Node, ["/status/truncated/text()", "/direct_message/truncated/text()"], ""),
        in_reply_to_status_id = text_or_default(Node, ["/status/in_reply_to_status_id/text()", "/direct_message/in_reply_to_status_id/text()"], ""),
        in_reply_to_user_id = text_or_default(Node, ["/status/in_reply_to_user_id/text()", "/direct_message/in_reply_to_user_id/text()"], ""),
        favorited = text_or_default(Node, ["/status/favorited/text()", "/direct_message/favorited/text()"], "")
    },
    case xmerl_xpath:string("/status/user|/direct_message/sender", Node) of
        [] -> Status;
        [UserNode] -> Status#status{ user = parse_user(UserNode) }
    end;

%% @private
parse_status(Body) when is_list(Body) ->
    case (catch xmerl_scan:string(Body, [{quiet, true}])) of
        {'EXIT', _} -> {error, Body};
        {error, _} -> {error, Body};
        Result ->
            {Xml, _Rest} = Result,
            [parse_status(Node) || Node <- xmerl_xpath:string("/status", Xml)]
    end.
    
%% @private
parse_messages(Body) ->
  case (catch xmerl_scan:string(Body, [{quiet, true}])) of
      {'EXIT', _} -> {error, Body};
      {error, _} -> {error, Body};
      Result ->
          {Xml, _Rest} = Result,
          [parse_message(Node) || Node <- lists:flatten([xmerl_xpath:string("/direct-messages/direct_message", Xml)])]
  end.

%% @private
parse_message(Node) when is_tuple(Node) ->
  #message{
    created_at = text_or_default(Node, ["/direct_message/created_at/text()"], ""), 
    id = text_or_default(Node, ["/direct_message/id/text()"], ""),
    text = text_or_default(Node, ["/direct_message/text/text()"], ""),
    sender_id = text_or_default(Node, ["/direct_message/sender_id/text()"], ""), 
    recipient_id = text_or_default(Node, ["/direct_message/recipient_id/text()"], ""), 
    sender_screen_name = text_or_default(Node, ["/direct_message/sender_screen_name/text()"], ""), 
    recipient_screen_name = text_or_default(Node, ["/direct_message/recipient_screen_name/text()"], ""), 
    sender = case xmerl_xpath:string("/direct_message/sender", Node) of
                [] -> "";
                [SenderNode] -> parse_user(SenderNode)
             end,
    recipient = case xmerl_xpath:string("/direct_message/recipient", Node) of
                  [] -> "";
                  [RecipientNode] -> parse_user(RecipientNode)
                end
  };

%% @private
parse_message(Body) when is_list(Body) ->
  case (catch xmerl_scan:string(Body, [{quiet, true}])) of
      {'EXIT', _} -> {error, Body};
      {error, _} -> {error, Body};
      Result ->
          {Xml, _Rest} = Result,
          [parse_message(Node) || Node <- xmerl_xpath:string("/direct_message", Xml)]
  end.

%% @private
parse_users(Body) ->
    case (catch xmerl_scan:string(Body, [{quiet, true}])) of
        {'EXIT', _} -> {error, Body};
        {error, _} -> {error, Body};
        Result ->
            {Xml, _Rest} = Result,
            [parse_user(Node) || Node <- xmerl_xpath:string("/users/user", Xml)]
    end.

%% @private
parse_user(Node) when is_tuple(Node) ->
    UserRec = #user{
        id = text_or_default(Node, ["/user/id/text()", "/sender/id/text()"], ""),
        name = text_or_default(Node, ["/user/name/text()", "/sender/name/text()"], ""),
        screen_name = text_or_default(Node, ["/user/screen_name/text()", "/sender/screen_name/text()"], ""),
        location = text_or_default(Node, ["/user/location/text()", "/sender/location/text()"], ""),
        description = text_or_default(Node, ["/user/description/text()", "/sender/description/text()"], ""),
        profile_image_url = text_or_default(Node, ["/user/profile_image_url/text()", "/sender/profile_image_url/text()"], ""),
        url = text_or_default(Node, ["/user/url/text()", "/sender/url/text()"], ""),
        protected = text_or_default(Node, ["/user/protected/text()", "/sender/protected/text()"], ""),
        followers_count = text_or_default(Node, ["/user/followers_count/text()", "/sender/followers_count/text()"], ""),
        profile_background_color = text_or_default(Node, ["/user/profile_background_color/text()"], ""),
        profile_text_color = text_or_default(Node, ["/user/profile_text_color/text()"], ""),
        profile_link_color = text_or_default(Node, ["/user/profile_link_color/text()"], ""),
        profile_sidebar_fill_color = text_or_default(Node, ["/user/profile_sidebar_fill_color/text()"], ""),
        profile_sidebar_border_color = text_or_default(Node, ["/user/profile_sidebar_border_color/text()"], ""),
        friends_count = text_or_default(Node, ["/user/friends_count/text()"], ""),
        created_at = text_or_default(Node, ["/user/created_at/text()"], ""),
        favourites_count = text_or_default(Node, ["/user/favourites_count/text()"], ""),
        utc_offset = text_or_default(Node, ["/user/utc_offset/text()"], ""),
        time_zone = text_or_default(Node, ["/user/time_zone/text()"], ""),
        following = text_or_default(Node, ["/user/following/text()"], ""),
        notifications = text_or_default(Node, ["/user/notifications/text()"], ""),
        statuses_count = text_or_default(Node, ["/user/statuses_count/text()"], "")
    },
    case xmerl_xpath:string("/user/status", Node) of
        [] -> UserRec;
        [StatusNode] -> UserRec#user{ status = parse_status(StatusNode) }
    end;

%% @private
parse_user(Body) when is_list(Body) ->
    case (catch xmerl_scan:string(Body, [{quiet, true}])) of
        {'EXIT', _} -> {error, Body};
        {error, _} -> {error, Body};
        Result ->
            {Xml, _Rest} = Result,
            [parse_user(Node) || Node <- xmerl_xpath:string("/user", Xml)]
    end.

%% @private
parse_rate_limit(Node) when is_tuple(Node) ->
  #rate_limit{
      reset_time = text_or_default(Node, ["/hash/reset-time/text()"], ""),
      reset_time_in_seconds = int_or_default(Node, ["/hash/reset-time-in-seconds/text()"], ""),
      remaining_hits = int_or_default(Node, ["/hash/remaining-hits/text()"], ""),
      hourly_limit = int_or_default(Node, ["/hash/hourly-limit/text()"], "")
  };

%% @private
parse_rate_limit(Body) when is_list(Body) ->
  case (catch xmerl_scan:string(Body, [{quiet, true}])) of
      {'EXIT', _} -> {error, Body};
      {error, _} -> {error, Body};
      Result ->
        {Xml, _Rest} = Result,
        [parse_rate_limit(Node) || Node <- xmerl_xpath:string("/hash", Xml)]
      end.

%% @private
parse_id(Node) ->
    Text = text_or_default(Node, ["/id/text()"], ""),
    twitter_client_utils:string_to_int(Text).

%% @private
text_or_default(_, [], Default) -> Default;
text_or_default(Xml, [Xpath | Tail], Default) ->
    Res = lists:foldr(
        fun(#xmlText{value = Val}, Acc) -> lists:append(Val, Acc);
           (_, Acc) -> Acc
        end,
        Default,
        case Xml of
          {error} -> Default;
          _ -> xmerl_xpath:string(Xpath, Xml)
        end
    ),
    text_or_default(Xml, Tail, Res).
    
%% @private
int_or_default(_Xml, [], Default) -> Default;
int_or_default(Xml, Xpath, Default) ->
  twitter_client_utils:string_to_int(text_or_default(Xml, Xpath, Default)).
