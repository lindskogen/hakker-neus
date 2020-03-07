import * as React from "react";
import { useCallback, useEffect, useState } from "react";
import { FlatList, ListRenderItem, RefreshControl, View } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNComment, HNStory } from "../common/types";
import { backgroundDark } from "../common/vars";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { CommentWithChildren } from "../components/CommentWithChildren";
import { Loader } from "../components/Loader";
import { useQuery } from "react-query";
import {
  fetchCommentsForItem,
  HNStoryWithComments
} from "../fetchers/fetchCommentsForItem";
import { EmptyStateIcon } from "../components/EmptyStateIcon";

interface Props {
  story: HNStoryWithComments;
  comments: HNComment[];
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
  isFetching: boolean;
  refetch: () => void;
}

const CommentsFlatList = ({
  navigation,
  story,
  comments,
  isFetching,
  refetch
}: Props) => {
  const user: string = story?.by.id ?? "undefined";

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

  return (
    <FlatList
      style={{ backgroundColor: backgroundDark }}
      data={comments}
      refreshControl={
        <RefreshControl
          refreshing={isFetching}
          onRefresh={() => refetch()}
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

export const CommentsList: React.FC<{
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  const { id } = navigation.state.params!;

  const [mounted, setMounted] = useState(false);

  const { data: story, isFetching, refetch } = useQuery<
    HNStoryWithComments,
    any
  >(
    ["comments", { id }],
    // @ts-ignore
    fetchCommentsForItem
  );

  useEffect(() => {
    setMounted(true);
  }, []);

  const comments = story?.kids.filter(
    (kid: HNComment | null) => kid && !!kid.text
  ) as HNComment[];

  const isLoading = isFetching || !mounted;

  if (isLoading || comments.length == 0) {
    return (
      <>
        {navigation.state.params!.story && (
          <CommentsListItemHeader
            navigation={navigation}
            story={navigation.state.params!.story}
          />
        )}
        {isLoading ? (
          <Loader backgroundColor={backgroundDark} />
        ) : (
          <View
            style={{
              flex: 1,
              justifyContent: "center",
              alignItems: "center",
              backgroundColor: backgroundDark
            }}
          >
            <EmptyStateIcon width={70} height={70} opacity={0.3} />
          </View>
        )}
      </>
    );
  }

  return (
    <CommentsFlatList
      story={story}
      navigation={navigation}
      comments={comments}
      isFetching={isFetching}
      refetch={refetch}
    />
  );
};
