import * as React from "react";
import { useContext, useEffect, useState } from "react";
import { formatDistanceStrict } from "date-fns";

const CurrentTimeContext = React.createContext(new Date());

const CurrentTimeContextProvider = CurrentTimeContext.Provider;

export const useCurrentTime = () => useContext(CurrentTimeContext);

export const CurrentTimeProvider: React.FC = ({ children }) => {
  const [now, setNow] = useState(new Date());

  useEffect(() => {
    const interval = setInterval(() => setNow(new Date()), 60000);

    return () => {
      clearInterval(interval);
    };
  }, []);

  return (
    <CurrentTimeContextProvider value={now}>
      {children}
    </CurrentTimeContextProvider>
  );
};

export const RelativeTime: React.FC<{ pastDate: Date }> = ({ pastDate }) => {
  const now = useCurrentTime();

  return <>{formatDistanceStrict(pastDate, now)}</>;
};
