## Introduction

To start, you should read our introductory guide to [Using the XML API](https://boardgamegeek.com/using_the_xml_api) and our [XML API terms of use](https://boardgamegeek.com/wiki/page/XML_API_Terms_of_Use#).

The XMLAPI2 is a new version of the XML API that is in BETA. For the old API see [BGG\_XML\_API](https://boardgamegeek.com/wiki/page/BGG_XML_API#). Each base URI is described and the various parameters are listed. The parameters and their values are URL-encoded in the standard manner.

For current information and discussions and source of this material see:  
[BoardGameGeek XML API](https://boardgamegeek.com/thread/99401/boardgamegeek-xml-api) or the guild since that thread is locked: [https://boardgamegeek.com/guild/1229](https://boardgamegeek.com/guild/1229)

Related wiki: [Data Mining](https://boardgamegeek.com/wiki/page/Data_Mining#) (based on previous XMLAPI).

Current bugs/enhancement requests: [XML API Enhancements](https://boardgamegeek.com/wiki/page/XML_API_Enhancements#)

## CSV Downloads

In addition to the XML API, we provide a single CSV file that includes the names, ids, ranks, and average rating for all of the games in the database. If you want all of the game names and ranks in the database, this is the preferred way to get them. You can find the a download link for the CSV here: [https://boardgamegeek.com/data\_dumps/bg\_ranks](https://boardgamegeek.com/data_dumps/bg_ranks) For licensing purposes, this data is considered to be part of the XML API.

## Root Path

The root path for all requests in the XMLAPI2 are prefixed as follows. These queries can be made only on boardgamegeek.com. Example path:

-   [https://boardgamegeek.com/xmlapi2/](https://boardgamegeek.com/xmlapi2/)

Avoid the _www_ subdomains, e.g. don't use [https://www.boardgamegeek.com/xmlapi2/](https://www.boardgamegeek.com/xmlapi2/). Their usage may [interfere with request authorization](https://boardgamegeek.com/thread/3492262/article/46120411#46120411).

## Rate Limit

BGG throttles the requests, which is to say that if you send requests too frequently, the server will give you 500 or 503 return codes, reporting that it is too busy. Currently, a 5-second wait between requests seems to suffice.

## Commands

Current usage is as follows, but this is in flux. The parts of the XML API that have not yet changed are not described below and follow the same syntax as the [BGG\_XML\_API](https://boardgamegeek.com/wiki/page/BGG_XML_API#). See thread mentioned above for updates on the XMLAPI2.

For all of the parameters mentioned below, the first parameter you list follows a **?** (question mark), and each subsequent parameter follows an **&** (ampersand).

### Thing Items

In the BGG database, any physical, tangible product is called a _thing_. The XMLAPI2 supports things of the following THINGTYPEs:

-   boardgame
-   boardgameexpansion
-   boardgameaccessory
-   videogame
-   rpgitem
-   rpgissue (for periodicals)

Note: [Max 20 items from XML API and XML API 2](https://boardgamegeek.com/thread/3336313/max-20-items-from-xml-api-and-xml-api-2)

Base URI: /xmlapi2/thing?_parameters_

| Parameter | Description |
| --- | --- |
| id=NNN | Specifies the id of the thing(s) to retrieve. To request multiple things with a single query, NNN can specify a comma-delimited list of ids. Maximum 20. |
| type=THINGTYPE | Specifies that, regardless of the type of thing asked for by id, the results are filtered by the THINGTYPE(s) specified. Multiple THINGTYPEs can be specified in a comma-delimited list. |
| versions=1 | Returns version info for the item. |
| videos = 1 | Returns videos for the item. |
| stats=1 | Returns ranking and rating stats for the item. |
| historical=1 | _Not currently supported._ Returns historical data over time. See page parameter. |
| marketplace=1 | Returns marketplace data. |
| comments=1 | Returns all comments about the item. Also includes ratings when commented. See page parameter. |
| ratingcomments=1 | Returns all ratings for the item. Also includes comments when rated. See page parameter. The ratingcomments and comments parameters cannot be used together, as the output always appears in the <comments> node of the XML; comments parameter takes precedence if both are specified. Ratings are sorted in ascending rating value. |
| page=NNN | Defaults to 1, controls the page of data to see for historical info, comments, and ratings data. |
| pagesize=NNN | Set the number of records to return in paging. Minimum is 10, maximum is 100. |
| from=YYYY-MM-DD | _Not currently supported._ |
| to=YYYY-MM-DD | _Not currently supported._ |

### Family Items

In the BGG database, more abstract or esoteric concepts are represented by something called a _family_. The XMLAPI2 supports families of the following FAMILYTYPEs:

-   rpg
-   rpgperiodical
-   boardgamefamily

Base URI: /xmlapi2/family?_parameters_

| Parameter | Description |
| --- | --- |
| id=NNN | Specifies the id of the family to retrieve. To request multiple families with a single query, NNN can specify a comma-delimited list of ids. |
| type=FAMILYTYPE | Specifies that, regardless of the type of family asked for by id, the results are filtered by the FAMILYTPE(s) specified. Multiple FAMILYTYPEs can be specified in a comma-delimited list. |

### Forum Lists

You can request a list of forums for a particular type/id through the XMLAPI2.

Base URI: /xmlapi2/forumlist?_parameters_

| Parameter | Description |
| --- | --- |
| id=NNN | Specifies the id of the type of database entry you want the forum list for. This is the id that appears in the address of the page when visiting a particular game in the database. |
| type=\\[thing,family\\] | The type of entry in the database. |

### Forums

You can request a list of threads in a particular forum through the XMLAPI2.

Base URI: /xmlapi2/forum?_parameters_

| Parameter | Description |
| --- | --- |
| id=NNN | Specifies the id of the forum. This is the id that appears in the address of the page when visiting a forum in the browser. |
| page=NNN | The page of the thread list to return; page size is 50. Threads in the thread list are sorted in order of most recent post. |

### Threads

With the XMLAPI2 you can request forum threads by thread id. A thread consists of some basic information about the thread and a series of _articles_ or individual postings.

Base URI: /xmlapi2/thread?_parameters_

| Parameter | Description |
| --- | --- |
| id=NNN | Specifies the id of the thread to retrieve. |
| minarticleid=NNN | Filters the results so that only articles with an equal or higher id than NNN will be returned. |
| minarticledate=YYYY-MM-DD | Filters the results so that only articles on the specified date or later will be returned. |
| minarticledate=YYYY-MM-DD%20HH%3AMM%3ASS | Filteres the results so that only articles after the specified date an time (HH:MM:SS) or later will be returned. |
| count=NNN | Limits the number of articles returned to no more than NNN (max 1000). |
| username=NAME | _Not currently supported._ |

### Users

With the XMLAPI2 you can request basic public profile information about a user by username.

Base URI: /xmlapi2/user?_parameters_

| Parameter | Description |
| --- | --- |
| name=NAME | Specifies the user name (only one user is requestable at a time). |
| buddies=1 | Turns on optional buddies reporting. Results are paged; see page parameter. |
| guilds=1 | Turns on optional guilds reporting. Results are paged; see page parameter. |
| hot=1 | Include the user's hot 10 list from their profile. Omitted if empty. |
| top=1 | Include the user's top 10 list from their profile. Omitted if empty. |
| domain=DOMAIN | Controls the domain for the users hot 10 and top 10 lists. The DOMAIN default is boardgame; valid values are: - boardgame - rpg - videogame |
| page=NNN | Specifies the page of buddy and guild results to return. The default page is 1 if you don't specify it; page size is 100 records (Current implementation seems to return 1000 records). The page parameter controls paging for both buddies and guilds list if both are specified. If a <buddies> or <guilds> node is empty, it means that you have requested a page higher than that needed to list all the buddies/guilds or, if you're on page 1, it means that that user has no buddies and is not part of any guilds. |

### Guilds

Request information about particular guilds.

Base URI: /xmlapi2/guild?_parameters_

| Parameter | Description |
| --- | --- |
| id=NNN | ID of the guild you want to view. |
| members=1 | Include member roster in the results. Member list is paged and sorted. |
| sort=SORTTYPE | Specifies how to sort the members list; default is username. Valid values are: - username - date |
| page=NNN | The page of the members list to return. Page size is 25. |

### Plays

Request plays logged by a particular user or for a particular item.

Base URI: /xmlapi2/plays?_parameters_

| Parameter | Description |
| --- | --- |
| username=NAME | Name of the player you want to request play information for. Data is returned in backwards-chronological form. You must include either a username or an id and type to get results. |
| id=NNN | Id number of the item you want to request play information for. Data is returned in backwards-chronological form. |
| type=TYPE | Type of the item you want to request play information for. Valid types include: - thing - family |
| mindate=YYYY-MM-DD | Returns only plays of the specified date or later. |
| maxdate=YYYY-MM-DD | Returns only plays of the specified date or earlier. |
| subtype=TYPE | Limits play results to the specified TYPE; boardgame is the default. Valid types include: - boardgame - boardgameexpansion - boardgameaccessory - boardgameintegration - boardgamecompilation - boardgameimplementation - rpg - rpgitem - videogame |
| page=NNN | The page of information to request. Page size is 100 records. |

### Collection

Request details about a user's collection.

Note that you should check the response status code... if it's 202 (vs. 200) then it indicates BGG has queued your request and you need to keep retrying (hopefully w/some delay between tries) until the status is not 202. More info at [Export collections has been updated (XMLAPI developers read this)](https://boardgamegeek.com/thread/1188687/export-collections-has-been-updated-xmlapi-develop)

Note that the default (or using subtype=boardgame) returns both boardgame and boardgameexpansion's in your collection... but incorrectly gives subtype=boardgame for the expansions. Workaround is to use excludesubtype=boardgameexpansion and make a 2nd call asking for subtype=boardgameexpansion

Base URI: /xmlapi2/collection?_parameters_

| Parameter | Description |
| --- | --- |
| username=NAME | Name of the user to request the collection for. |
| version=1 | Returns version info for each item in your collection. |
| subtype=TYPE | Specifies which collection you want to retrieve. TYPE may be boardgame, boardgameexpansion, boardgameaccessory, rpgitem, rpgissue, or videogame; the default is boardgame |
| excludesubtype=TYPE | Specifies which subtype you want to exclude from the results. |
| id=NNN | Filter collection to specifically listed item(s). NNN may be a comma-delimited list of item ids. |
| brief=1 | Returns more abbreviated results. |
| stats=1 | Returns expanded rating/ranking info for the collection. |
| own=\\[0,1\\] | Filter for owned games. Set to 0 to exclude these items so marked. Set to 1 for returning owned games and 0 for non-owned games. |
| rated=\\[0,1\\] | Filter for whether an item has been rated. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| played=\\[0,1\\] | Filter for whether an item has been played. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| comment=\\[0,1\\] | Filter for items that have been commented. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| trade=\\[0,1\\] | Filter for items marked for trade. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| want=\\[0,1\\] | Filter for items wanted in trade. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| wishlist=\\[0,1\\] | Filter for items on the wishlist. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| wishlistpriority=\\[1-5\\] | Filter for wishlist priority. Returns only items of the specified priority. |
| preordered=\\[0,1\\] | Filter for pre-ordered games Returns only items of the specified priority. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| wanttoplay=\\[0,1\\] | Filter for items marked as wanting to play. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| wanttobuy=\\[0,1\\] | Filter for ownership flag. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| prevowned=\\[0,1\\] | Filter for games marked previously owned. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| hasparts=\\[0,1\\] | Filter on whether there is a comment in the Has Parts field of the item. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| wantparts=\\[0,1\\] | Filter on whether there is a comment in the Wants Parts field of the item. Set to 0 to exclude these items so marked. Set to 1 to include only these items so marked. |
| minrating=\\[1-10\\] | Filter on minimum personal rating assigned for that item in the collection. |
| rating=\\[1-10\\] | Filter on maximum personal rating assigned for that item in the collection. \\[Note: Although you'd expect it to be _maxrating_, it's _rating_.\\] |
| minbggrating=\\[1-10\\] | Filter on minimum BGG rating for that item in the collection. Note: 0 is ignored... you can use -1 though, for example min -1 and max 1 to get items w/no bgg rating. |
| bggrating=\\[1-10\\] | Filter on maximum BGG rating for that item in the collection. \\[Note: Although you'd expect it to be _maxbggrating_, it's _bggrating_.\\] |
| minplays=NNN | Filter by minimum number of recorded plays. |
| maxplays=NNN | Filter by maximum number of recorded plays. \\[Note: Although the two maxima parameters above lack the _max_ part, this one really is _maxplays_.\\] |
| showprivate=1 | Filter to show private collection info. Only works when viewing your own collection and you are logged in (include cookies from logging into the website in request). |
| collid=NNN | Restrict the collection results to the single specified collection id. Collid is returned in the results of normal queries as well. |
| modifiedsince=YY-MM-DD | Restricts the collection results to only those whose status (own, want, fortrade, etc.) has changed or been added since the date specified (does not return results for deletions). Time may be added as well: modifiedsince=YY-MM-DD%20HH:MM:SS |

### Hot Items

You can retrieve the list of most active items on the site.

Base URI: /xmlapi2/hot?_parameter_

| Parameter | Description |
| --- | --- |
| type=TYPE | There are a number of different hot lists available on the site. Valid types include: - boardgame - rpg - videogame - boardgameperson - rpgperson - boardgamecompany - rpgcompany - videogamecompany |

### Geeklist

_Not yet updated to XMLAPI2._

### Search

You can search for items from the database by name.

Base URI: /xmlapi2/search?_parameters_

| Parameter | Description |
| --- | --- |
| query=SEARCH\\_QUERY | Returns all types of Items that match SEARCH\\_QUERY. Spaces in the SEARCH\\_QUERY are replaced by a + |
| type=TYPE | Return all items that match SEARCH\\_QUERY of type TYPE. TYPE might be rpgitem, videogame, boardgame, boardgameaccessory, boardgameexpansion or boardgamedesigner . You can return multiple types by listing them separated by commas, e.g. type=TYPE1,TYPE2,TYPE3 |
| exact=1 | Limit results to items that match the SEARCH\\_QUERY exactly |

## XML Schema

see [Lesser Known Elements](https://boardgamegeek.com/thread/2794186/lesser-known-elements)