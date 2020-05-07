package main

import (
	"fmt"
	blockstorageQuotasets "github.com/gophercloud/gophercloud/openstack/blockstorage/extensions/quotasets"
	"github.com/gophercloud/gophercloud/openstack/compute/v2/extensions/limits"
	"github.com/gophercloud/utils/openstack/clientconfig"
	"github.com/spf13/cobra"
	"os"
	"strings"
	"text/tabwriter"
)

func usage() {
	fmt.Println("Only one metric maybe selected when using the \"usage_only\" flag")
}

var cmd = &cobra.Command{
		Use:   "get_cloud_usage -flag --flag",
		Short: "Collects information about resource usage from OpenStack cloud",
		Run: func(cmd *cobra.Command, args []string) {
			if cloudName == "" {
				cloudName = os.Getenv("OS_CLOUD")
			}
			if cloudName == "" {
				fmt.Println("No cloud name was found. Please define via \"-l\" flag, or through OS_CLOUD environmental variable")
				os.Exit(2)
			}
			opts := &clientconfig.ClientOpts{
				Cloud:        cloudName,
			}


			flagCount := 0
			if cores {
				flagCount +=1
			}
			if instances {
				flagCount +=1
			}
			if securitygroups {
				flagCount +=1
			}
			if volumes {
				flagCount +=1
			}
			if volumestorage {
				flagCount +=1
			}
			if servergroups {
				flagCount +=1
			}
			if ram {
				flagCount +=1
			}

			if flagCount > 1 && usageonly {
				usage()
				return
			}

			var volumeUsage blockstorageQuotasets.QuotaUsageSet
			if volumes || volumestorage || flagCount != 1 {
				volumeUsage = get_volume_usage(opts)
			}
			computeLimits := get_compute_limits(opts)



			if usageonly {
				if cores {
					fmt.Println(computeLimits.TotalCoresUsed)
				} else if instances {
					fmt.Println(computeLimits.TotalInstancesUsed)
				} else if securitygroups {
					fmt.Println(computeLimits.TotalSecurityGroupsUsed)
				} else if volumes {
					fmt.Println(volumeUsage.Volumes.InUse)
				} else if volumestorage {
					fmt.Println(volumeUsage.Gigabytes.Limit)
				} else if servergroups {
					fmt.Println(computeLimits.TotalServerGroupsUsed)
				} else if ram {
					fmt.Println(computeLimits.TotalRAMUsed)
				}
			} else {
				w := new(tabwriter.Writer)
				w.Init(os.Stdout, 8, 8, 1, ' ', 0)
				defer w.Flush()
				line := strings.Repeat("-", 13)
				fmt.Fprintf(w, "\n |%21s |%12s |%12s |%12s |", "Resource", "Utilization", "Max", "Used")
				fmt.Fprintf(w,"\n +%s+%s+%s+%s+",strings.Repeat("-",22), line, line ,line)
				
				
				
				

				if cores || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"Core",
						float32(computeLimits.TotalCoresUsed)/float32(computeLimits.MaxTotalCores)*100,
						computeLimits.MaxTotalCores,computeLimits.TotalCoresUsed)
				}
				if instances || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"Instances",
						float32(computeLimits.TotalInstancesUsed)/float32(computeLimits.MaxTotalInstances)*100,
						computeLimits.MaxTotalInstances,computeLimits.TotalInstancesUsed)
				} 
				if securitygroups || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"SecurityGroups",
						float32(computeLimits.TotalSecurityGroupsUsed)/float32(computeLimits.MaxSecurityGroups)*100,
						computeLimits.MaxSecurityGroups,computeLimits.TotalSecurityGroupsUsed)
				}
				if volumes || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"Volumes",
						float32(volumeUsage.Volumes.InUse)/float32(volumeUsage.Volumes.Limit)*100,
						volumeUsage.Volumes.Limit,volumeUsage.Volumes.InUse)
				}
				if volumestorage || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"Volume (GB)",
						float32(volumeUsage.Gigabytes.InUse)/float32(volumeUsage.Gigabytes.Limit)*100,
						volumeUsage.Gigabytes.Limit,volumeUsage.Gigabytes.InUse)
				}
				if servergroups || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"ServerGroups",
						float32(computeLimits.TotalServerGroupsUsed)/float32(computeLimits.MaxServerGroups)*100,
						computeLimits.MaxServerGroups,computeLimits.TotalServerGroupsUsed)
				}
				if ram || flagCount == 0 {
					fmt.Fprintf(w, "\n |%21s |%11.0f%% |%12d |%12d |",
						"RAM",
						float32(computeLimits.TotalRAMUsed)/float32(computeLimits.MaxTotalRAMSize)*100,
						computeLimits.MaxTotalRAMSize,computeLimits.TotalRAMUsed)
				}
				fmt.Fprintf(w, "\n")
			}
			
		},
	}


func get_volume_usage(opts *clientconfig.ClientOpts) (volumeUsage blockstorageQuotasets.QuotaUsageSet) {
	cloud, err := clientconfig.GetCloudFromYAML(opts)
	if err != nil {
		panic(err)
	}
	tenantId := cloud.AuthInfo.ProjectID
	volumeClient, err := clientconfig.NewServiceClient("volume", opts)
	if err != nil {
		panic(err)
	}
	volumeUsage, err = blockstorageQuotasets.GetUsage(volumeClient, tenantId).Extract()
	if err != nil {
		panic(err)
	}

	return volumeUsage
}


func get_compute_limits(opts *clientconfig.ClientOpts) (instances limits.Absolute) {
	computeClient, err := clientconfig.NewServiceClient("compute", opts)
	if err != nil {
		panic(err)
	}

	computeLimits, err := limits.Get(computeClient, nil).Extract()
	if err != nil {
		panic(err)
	}
	return computeLimits.Absolute
}


	var cores, ram, instances, securitygroups, volumes, servergroups, volumestorage, usageonly bool
	var cloudName string

func main(){
	cmd.PersistentFlags().BoolVarP(&usageonly, "usage_only", "u", false, "List only usage not quota")
	cmd.PersistentFlags().BoolVarP(&cores, "cores", "c", false,"Get cores usage")
	cmd.PersistentFlags().BoolVarP(&instances, "instances", "i", false,"Get instances usage")
	cmd.PersistentFlags().BoolVarP(&securitygroups, "securitygroups", "y", false,"Get security groups usage")
	cmd.PersistentFlags().BoolVarP(&volumes, "volumes", "v", false,"Get volumes usage")
	cmd.PersistentFlags().BoolVarP(&servergroups, "servergroups", "g", false,"Get server groups usage")
	cmd.PersistentFlags().BoolVarP(&volumestorage, "volumestorage", "s", false,"Get volume storage usage")
    cmd.PersistentFlags().BoolVarP(&ram, "ram","r",false, "Get ram usage")
	cmd.PersistentFlags().StringVarP(&cloudName, "cloud","l","", "Cloud name to use from clouds.yaml")
	cmd.Execute()
}
