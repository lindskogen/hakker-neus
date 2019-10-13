import * as d3 from "d3-scale-chromatic";
import gql from "graphql-tag";
import * as React from "react";
import { FlatList, RefreshControl, View } from "react-native";
import { useQuery } from "urql";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { CommentWithChildren } from "../components/CommentWithChildren";
import { Loader } from "../components/Loader";

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
        timeISO
      }
    `,
    variables: { id }
  });

  if (!data) {
    return (
      <View style={{ flex: 1 }}>
        {navigation.state.params.story && (
          <CommentsListItemHeader
            navigation={navigation}
            story={navigation.state.params.story}
          />
        )}
        <Loader backgroundColor={d3.interpolateBlues(0.6)} />
      </View>
    );
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
          <CommentsListItemHeader navigation={navigation} story={story} />
        ) : (
          <CommentWithChildren
            op={story.by.id}
            comment={item}
            depth={0}
            navigation={navigation}
          />
        )
      }
    />
  );
};
