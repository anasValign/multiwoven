import SteppedForm from "../SteppedForm";
import SelectDataSourceForm from "./SelectDataSourceForm";
import SecondForm from "./SecondForm";

const Sources = () => {
  const steps = [
    {
      formKey: "first",
      name: "Select a data source",
      component: <SelectDataSourceForm />,
    },
    {
      formKey: "second",
      name: "Second Form",
      component: <SecondForm />,
    },
  ];

  return <SteppedForm steps={steps} />;
};

export default Sources;
