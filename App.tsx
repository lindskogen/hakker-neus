import * as d3 from "d3-scale-chromatic";
import gql from "graphql-tag";
import { AllHtmlEntities } from "html-entities";
import HTML from "html-parse-stringify";
import * as React from "react";
import {
  ActivityIndicator,
  FlatList,
  Linking,
  Platform,
  PlatformIOSStatic,
  RefreshControl,
  SafeAreaView,
  StatusBar,
  Text,
  TouchableOpacity,
  View
} from "react-native";
import Swipeable from "react-native-swipeable";
import { createAppContainer } from "react-navigation";
import { createStackNavigator } from "react-navigation-stack";
import { createClient, Provider, useQuery } from "urql";

const entities = new AllHtmlEntities();

const padding = 10;

const client = createClient({
  url: "https://www.graphqlhub.com/graphql"
});

function Loader({ backgroundColor }) {
  return (
    <View
      style={{
        flex: 1,
        justifyContent: "center",
        alignItems: "center",
        backgroundColor
      }}
    >
      <ActivityIndicator color={"white"} size={"large"} />
    </View>
  );
}

const NewsList = ({ navigation }) => {
  const [{ data, fetching }, executeQuery] = useQuery({
    query: gql`
      query Query {
        hn {
          topStories {
            id
            descendants
            type
            title
            by {
              id
            }
            text
            url
            score
          }
        }
      }
    `
  });

  if (!data) {
    return <Loader backgroundColor={d3.interpolateOranges(0.5)} />;
  }

  const stories = data.hn.topStories;

  return (
    <FlatList
      data={stories}
      refreshControl={
        <RefreshControl
          refreshing={fetching}
          onRefresh={() => executeQuery({ requestPolicy: "network-only" })}
          tintColor={"white"}
        />
      }
      keyExtractor={item => item.id}
      renderItem={({ item: story, index }) => (
        <Swipeable
          rightContent={
            <View
              style={{
                backgroundColor: d3.interpolateBlues(1),
                flex: 1,
                justifyContent: "center",
                alignItems: "flex-start",
                paddingLeft: 20
              }}
            >
              <Text
                style={{
                  fontSize: 50,
                  fontFamily: "Helvetica Neue",
                  color: "white",
                  textShadowColor: "rgba(0, 0, 0, 0.1)",
                  textShadowOffset: { height: 0, width: 0 },
                  textShadowRadius: 1
                }}
              >
                {story.descendants}
              </Text>
            </View>
          }
          onRightActionRelease={() =>
            navigation.navigate({
              routeName: "Comments",
              params: { id: story.id }
            })
          }
          key={story.id}
        >
          <View
            style={{
              padding,
              minHeight: 100,
              backgroundColor: d3.interpolateOranges(
                (index / stories.length) * 0.5 + 0.5
              )
            }}
          >
            <TouchableOpacity onPress={() => Linking.openURL(story.url)}>
              <Text
                style={{
                  fontSize: (Platform as PlatformIOSStatic).isPad ? 30 : 25,
                  fontFamily: "Helvetica Neue",
                  fontWeight: "300",
                  color: "white",
                  textShadowColor: "rgba(0, 0, 0, 0.1)",
                  textShadowOffset: { height: 0, width: 0 },
                  textShadowRadius: 1
                }}
              >
                {story.title}
              </Text>
            </TouchableOpacity>
            <Text
              style={{
                position: "absolute",
                right: 20,
                bottom: 20,
                fontSize: 50,
                fontFamily: "Helvetica Neue",
                color: "white",
                opacity: 0.3,
                textShadowColor: "rgba(0, 0, 0, 0.1)",
                textShadowOffset: { height: 0, width: 0 },
                textShadowRadius: 1
              }}
            >
              {story.score}
            </Text>
          </View>
        </Swipeable>
      )}
    />
  );
};

function formatTag(tag: IDoc, index: number) {
  if (tag.type === "text") {
    return tag.content;
  } else if (tag.name === "p") {
    return (
      <Text key={index}>
        {"\n\n"}
        <Text style={{ paddingVertical: 10 }}>
          {tag.children.map((childTag, i) => formatTag(childTag, i))}
        </Text>
      </Text>
    );
  } else if (tag.name === "a") {
    return (
      <Text
        key={index}
        style={{ textDecorationLine: "underline" }}
        onPress={() => Linking.openURL(tag.attrs.href)}
      >
        {tag.children.map((childTag, i) => formatTag(childTag, i))}
      </Text>
    );
  } else if (tag.name === "i") {
    return (
      <Text key={index} style={{ fontStyle: "italic" }}>
        {tag.children.map((childTag, i) => formatTag(childTag, i))}
      </Text>
    );
  } else {
    return JSON.stringify(tag);
  }
}

interface IDoc {
  type: string;
  content?: string;
  voidElement: boolean;
  name: string;
  attrs: {};
  children: IDoc[];
}

function parseHTML(comment: string): IDoc {
  const astRoot: IDoc[] = HTML.parse(
    "<div>" + entities.decode(comment) + "</div>"
  );
  return astRoot[0];
}

function formatHTMLContent(comment: string) {
  const astRoot = parseHTML(comment);
  return <>{astRoot.children.map((tag, index) => formatTag(tag, index))}</>;
}

function CommentWithChildren({ comment }: { comment: ItemT }) {
  return (
    <View
      style={{
        padding,
        minHeight: 100,
        backgroundColor: d3.interpolateBlues(0.6),
        borderBottomColor: "black",
        borderBottomWidth: 1
      }}
    >
      <Text
        style={{
          fontSize: 10,
          fontFamily: "Helvetica Neue",
          color: "white",
          textTransform: "uppercase"
        }}
      >
        {comment.by.id}
      </Text>
      <Text
        style={{
          fontSize: 16,
          fontFamily: "Helvetica Neue",
          color: "white"
        }}
        onPress={() => console.log(parseHTML(comment.text))}
      >
        {formatHTMLContent(comment.text)}
      </Text>
      {(comment.kids || []).filter(kid => !!kid.text).map(kid => (
        <CommentWithChildren key={kid.id} comment={kid} />
      ))}
    </View>
  );
}

const CommentsList = ({ navigation }) => {
  const { id } = navigation.state.params;
  const [{ data, fetching }, executeQuery] = useQuery({
    query: gql`
      query CommentsQuery($id: Int!) {
        hn {
          item(id: $id) {
            id
            type
            descendants
            title
            kids {
              ...Comment
              kids {
                ...Comment
                kids {
                  ...Comment
                  kids {
                    ...Comment
                  }
                }
              }
            }
            by {
              id
            }
            text
            url
            score
          }
        }
      }

      fragment Comment on HackerNewsItem {
        id
        type
        by {
          id
        }
        text
        url
        score
      }
    `,
    variables: { id }
  });

  if (!data) {
    return <Loader backgroundColor={d3.interpolateBlues(0.6)} />;
  }

  const comments = data.hn.item.kids;

  return (
    <FlatList
      style={{ backgroundColor: "black" }}
      data={comments}
      refreshControl={
        <RefreshControl
          refreshing={fetching}
          onRefresh={() => executeQuery({ requestPolicy: "network-only" })}
          tintColor={"white"}
        />
      }
      keyExtractor={item => item.id}
      renderItem={({ item: comment, index }) => (
        <CommentWithChildren comment={comment} />
      )}
    />
  );
};

const AppNavigator = createStackNavigator(
  {
    Home: {
      screen: NewsList
    },
    Comments: { screen: CommentsList }
  },
  {
    headerMode: "none"
  }
);

const NavigationContainer = createAppContainer(AppNavigator);

export default function AppWrapper() {
  return (
    <Provider value={client}>
      <StatusBar barStyle={"light-content"} />
      <SafeAreaView style={{ flex: 1, padding, backgroundColor: "black" }}>
        <NavigationContainer />
      </SafeAreaView>
    </Provider>
  );
}
