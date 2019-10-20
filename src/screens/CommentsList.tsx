import * as d3 from "d3-scale-chromatic";
import gql from "graphql-tag";
import * as React from "react";
import { useCallback } from "react";
import { FlatList, ListRenderItem, RefreshControl, View } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { useQuery } from "urql";
import { HNComment, HNStory } from "../common/types";
import { backgroundDark } from "../common/vars";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { CommentWithChildren } from "../components/CommentWithChildren";
import { Loader } from "../components/Loader";

interface HNStoryWithComments extends HNStory {
  kids: HNComment[];
}

export const CommentsList: React.FC<{
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  const { id } = navigation.state.params!;
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

  const story: HNStoryWithComments | undefined = data
    ? data.hn.item
    : undefined;
  const user: string = story ? story.by.id : "undefined";

  const renderItem: ListRenderItem<HNComment> = useCallback(
    ({ item }) => (
      <CommentWithChildren
        op={user}
        comment={item}
        depth={0}
        navigation={navigation}
      />
    ),
    [user, navigation]
  );

  if (!story) {
    return (
      <View style={{ flex: 1 }}>
        {navigation.state.params!.story && (
          <CommentsListItemHeader
            navigation={navigation}
            story={navigation.state.params!.story}
          />
        )}
        <Loader backgroundColor={d3.interpolateBlues(0.6)} />
      </View>
    );
  }

  const comments = story.kids.filter(kid => !!kid.text);

  return (
    <FlatList
      style={{ backgroundColor: backgroundDark }}
      data={comments}
      refreshControl={
        <RefreshControl
          refreshing={fetching}
          onRefresh={() => executeQuery({ requestPolicy: "network-only" })}
          tintColor={"white"}
        />
      }
      ListHeaderComponent={
        <CommentsListItemHeader navigation={navigation} story={story} />
      }
      keyExtractor={item => String(item.id)}
      renderItem={renderItem}
    />
  );
};
