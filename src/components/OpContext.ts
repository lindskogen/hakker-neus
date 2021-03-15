import { default as React, useContext } from "react";

const OpContext = React.createContext<string>("deleted");

export const OpContextProvider = OpContext.Provider;

export const useOp = () => useContext(OpContext);
