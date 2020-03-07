import * as React from "react";
import { useCallback, useEffect, useState } from "react";
import {
  FlatList,
  ListRenderItem,
  RefreshControl,
  ScrollView,
  Text
} from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNComment, HNStory } from "../common/types";
import { backgroundDark, fontFamily, padding } from "../common/vars";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { CommentWithChildren } from "../components/CommentWithChildren";
import { Loader } from "../components/FullPageLoader";
import { useQuery } from "react-query";
import {
  fetchCommentsForItem,
  HNStoryWithComments
} from "../fetchers/fetchCommentsForItem";
import { EmptyStateIcon } from "../components/EmptyStateIcon";
import { FullPageView } from "../components/FullPageView";

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
      contentContainerStyle={{ paddingBottom: padding * 3 }}
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

function EmptyCommentsView() {
  return (
    <>
      <EmptyStateIcon width={70} height={70} opacity={0.3} />
      <Text
        style={{
          fontFamily,
          color: "rgba(255, 255, 255, 0.3)",
          fontWeight: "300",
          fontSize: 24
        }}
      >
        No comments here
      </Text>
    </>
  );
}

export const CommentsList: React.FC<{
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  const { id } = navigation.state.params!;
  const [isRefreshing, setRefreshing] = useState(false);

  const [mounted, setMounted] = useState(false);

  const { data: story, isFetching, refetch } = useQuery<
    HNStoryWithComments,
    any
  >(
    ["comments", { id }],
    // @ts-ignore
    fetchCommentsForItem,
    {
      onSettled: () => setRefreshing(false),
      refetchOnWindowFocus: false
    }
  );

  const onRefresh = () => {
    setRefreshing(true);
    return refetch();
  };

  useEffect(() => {
    setMounted(true);
  }, []);

  const comments = story?.kids.filter(
    (kid: HNComment | null) => kid && !!kid.text
  ) as HNComment[];

  const showFullPageSpinner = isFetching || (!mounted && !isRefreshing);

  if (!story || comments.length == 0) {
    return (
      <ScrollView
        contentContainerStyle={{ flex: 1 }}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={"white"}
          />
        }
      >
        {navigation.state.params!.story && (
          <CommentsListItemHeader
            navigation={navigation}
            story={navigation.state.params!.story}
          />
        )}
        <FullPageView backgroundColor={backgroundDark}>
          {showFullPageSpinner ? <Loader /> : <EmptyCommentsView />}
        </FullPageView>
      </ScrollView>
    );
  }

  return (
    <CommentsFlatList
      story={story}
      navigation={navigation}
      comments={comments}
      isFetching={isRefreshing}
      refetch={onRefresh}
    />
  );
};
