import * as d3 from "d3-scale-chromatic";
import gql from "graphql-tag";
import * as React from "react";
import {
  FlatList,
  RefreshControl,
  Share,
  TouchableOpacity
} from "react-native";
import { useQuery } from "urql";
import { CommentWithChildren } from "../components/CommentWithChildren";
import { Loader } from "../components/Loader";
import { NewsListItem } from "../components/NewsListItem";
import { NewsListItemText } from "../components/NewsListItemText";

export const CommentsList = ({ navigation }) => {
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
                    kids {
                      ...Comment
                    }
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
        timeISO
      }
    `,
    variables: { id }
  });

  if (!data) {
    return <Loader backgroundColor={d3.interpolateBlues(0.6)} />;
  }

  const story = data.hn.item;
  const comments = story.kids.filter(kid => !!kid.text);

  return (
    <FlatList
      style={{ backgroundColor: "black" }}
      data={[story, ...comments]}
      refreshControl={
        <RefreshControl
          refreshing={fetching}
          onRefresh={() => executeQuery({ requestPolicy: "network-only" })}
          tintColor={"white"}
        />
      }
      keyExtractor={item => item.id}
      renderItem={({ item, index }) =>
        index === 0 ? (
          <NewsListItem backgroundColor={d3.interpolateOranges(0.65)}>
            <TouchableOpacity
              style={{ flex: 1 }}
              onLongPress={() => {
                Share.share({
                  title: item.title,
                  url: "https://news.ycombinator.com/item?id=" + item.id
                });
              }}
              onPress={() => {
                navigation.navigate({
                  routeName: "Browser",
                  params: { url: item.url }
                });
              }}
            >
              <NewsListItemText>{story.title}</NewsListItemText>
            </TouchableOpacity>
          </NewsListItem>
        ) : (
          <CommentWithChildren comment={item} depth={0} navigation={navigation} />
        )
      }
    />
  );
};
